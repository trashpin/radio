// Marion County Event Discovery Engine.
//
// Multiple Sources -> Discovery Engine -> Verification -> Deduplication ->
// Admin Approval -> events -> Discover. Ticketmaster is Source #1 through
// this pipeline, not the whole event system -- additional sources plug in
// by adding one entry to SOURCE_CONNECTORS below; nothing else changes.
//
// This function NEVER writes directly to `public.events`. It writes
// normalized candidates into `public.discovered_events` for admin review,
// and only promotes a candidate into `events` when its source has
// `auto_publish = true` (a per-source flag an admin flips on once that
// source's quality is proven -- every source starts false).
//
// Modes:
//   dryRun: true  (default) -- runs discovery + classification, writes
//                    NOTHING to the database, just returns the counts a
//                    real run would produce. Use this to review a new
//                    source before trusting it.
//   dryRun: false -- writes to discovered_events (and to events, only for
//                    auto_publish sources) and updates each source's
//                    last_run_* stats.
//
// Deploy: supabase functions deploy marion-event-discovery
// Secrets required: TICKETMASTER_API_KEY (for the ticketmaster connector)
// Invoke (service-role key as bearer -- admin/maintenance action):
//   POST {SUPABASE_URL}/functions/v1/marion-event-discovery
//   body: { "dryRun": true, "sourceKeys": ["ticketmaster"] }  -- sourceKeys
//   omitted or empty runs every enabled source.

const DEFAULT_SUPABASE_URL = "https://qqeyvhcgirmfokoftiuz.supabase.co";

function resolveBaseUrl(): string {
  const raw = (Deno.env.get("SUPABASE_URL") ?? "").trim();
  const url = raw.length > 0 ? raw : DEFAULT_SUPABASE_URL;
  return url.replace(/\/+$/, "");
}
function buildSupabaseUrl(path: string): string {
  return `${resolveBaseUrl()}/${path.replace(/^\/+/, "")}`;
}

const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  Deno.env.get("SUPABASE_SERVICE_KEY") ?? "";
const SB = { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` };

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function sbGet(path: string): Promise<any[]> {
  const r = await fetch(buildSupabaseUrl(`rest/v1/${path}`), { headers: SB });
  if (!r.ok) throw new Error(`GET ${path} -> ${r.status}: ${(await r.text()).slice(0, 300)}`);
  return r.json();
}
async function sbUpsert(path: string, body: unknown, prefer: string): Promise<any> {
  const r = await fetch(buildSupabaseUrl(`rest/v1/${path}`), {
    method: "POST",
    headers: { ...SB, "Content-Type": "application/json", Prefer: prefer },
    body: JSON.stringify(body),
  });
  if (!r.ok) throw new Error(`POST ${path} -> ${r.status}: ${(await r.text()).slice(0, 400)}`);
  const text = await r.text();
  return text ? JSON.parse(text) : null;
}
async function sbPatch(path: string, body: unknown): Promise<void> {
  const r = await fetch(buildSupabaseUrl(`rest/v1/${path}`), {
    method: "PATCH",
    headers: { ...SB, "Content-Type": "application/json", Prefer: "return=minimal" },
    body: JSON.stringify(body),
  });
  if (!r.ok) throw new Error(`PATCH ${path} -> ${r.status}: ${(await r.text()).slice(0, 400)}`);
}

// ---------------------------------------------------------------------------
// Normalized event shape every connector must produce. Only [name] is
// required -- everything else is left null when the source doesn't provide
// it (spec: "Do not invent missing information").
// ---------------------------------------------------------------------------
interface NormalizedEvent {
  sourceEventId?: string | null;
  sourceUrl?: string | null;
  name: string;
  description?: string | null;
  startDate?: string | null; // YYYY-MM-DD
  endDate?: string | null;
  startTime?: string | null; // HH:MM:SS
  endTime?: string | null;
  venueName?: string | null;
  address?: string | null;
  city?: string | null;
  zip?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  website?: string | null;
  ticketUrl?: string | null;
  imageUrl?: string | null;
  organizer?: string | null;
  contact?: string | null;
  costInfo?: string | null;
  category?: string | null;
  interestTags?: string[];
  raw?: unknown;
}

// ---------------------------------------------------------------------------
// Marion County verification -- spec: "Do not rely solely on the event
// title... do not import events simply because a website happens to mention
// Marion County." Real coordinates are checked against the FCC's free public
// Census Block API (authoritative county geocoding); when there are no
// coordinates, the community name is checked against the exact list of real
// Marion County communities the spec provided.
// ---------------------------------------------------------------------------
const MARION_COMMUNITIES = new Set([
  "ocala", "belleview", "dunnellon", "silver springs", "silver springs shores",
  "ocklawaha", "reddick", "citra", "mcintosh", "orange springs",
  "fort mccoy", "anthony", "summerfield", "weirsdale",
]);

const FCC_BLOCK_URL = "https://geo.fcc.gov/api/census/block/find";
const countyCache = new Map<string, string | null>();

async function resolveCountyByCoords(lat: number, lng: number): Promise<string | null> {
  const key = `${lat.toFixed(4)},${lng.toFixed(4)}`;
  if (countyCache.has(key)) return countyCache.get(key)!;
  try {
    const r = await fetch(`${FCC_BLOCK_URL}?latitude=${lat}&longitude=${lng}&format=json`);
    if (!r.ok) {
      countyCache.set(key, null);
      return null;
    }
    const data = await r.json();
    const name = (data?.County?.name as string | undefined) ?? null;
    countyCache.set(key, name);
    return name;
  } catch {
    countyCache.set(key, null);
    return null;
  }
}

type LocationVerdict = "confirmed_marion" | "confirmed_other_county" | "uncertain";

/** The FCC Census Block API returns full county names like "Marion County"
 * -- not the bare "Marion" -- so this strips a trailing " County"/" Parish"
 * before comparing. An earlier version compared the raw string directly,
 * which meant genuine Marion County results (returned as "Marion County")
 * never matched and were wrongly rejected as "outside the county." */
function stripCountySuffix(county: string): string {
  return county.replace(/\s+(county|parish)$/i, "").trim();
}
function bareCountyName(county: string): string {
  return stripCountySuffix(county).toLowerCase();
}

async function verifyMarionCounty(
  ev: NormalizedEvent,
): Promise<{ verdict: LocationVerdict; county: string | null }> {
  if (ev.latitude != null && ev.longitude != null) {
    const county = await resolveCountyByCoords(ev.latitude, ev.longitude);
    if (county && bareCountyName(county) === "marion") {
      return { verdict: "confirmed_marion", county };
    }
    if (county) return { verdict: "confirmed_other_county", county };
  }
  const city = (ev.city ?? "").trim().toLowerCase();
  if (city && MARION_COMMUNITIES.has(city)) {
    return { verdict: "confirmed_marion", county: "Marion" };
  }
  return { verdict: "uncertain", county: null };
}

// ---------------------------------------------------------------------------
// Deduplication -- compares a candidate against both already-published
// `events` and other already-discovered rows across ALL sources (the same
// concert can appear via Ticketmaster and a venue calendar). High-confidence
// (matching name via trigram similarity + same date + same venue/near
// coordinates) is marked a duplicate outright; a partial match is sent to
// review instead of guessed at.
// ---------------------------------------------------------------------------
interface ExistingCandidate {
  id: string;
  name: string;
  event_date: string | null;
  latitude: number | null;
  longitude: number | null;
  venue_name?: string | null;
  city?: string | null;
}

function haversineMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function normalizeName(s: string): string {
  return s.toLowerCase().replace(/[^a-z0-9 ]/g, "").replace(/\s+/g, " ").trim();
}

// Lightweight trigram-free similarity (Dice coefficient over character
// bigrams) -- avoids a round trip to Postgres per comparison; the DB-side
// pg_trgm index (added in the schema) is available for a future admin
// "search similar" tool even though this pass does the scoring in-process.
function bigramSimilarity(a: string, b: string): number {
  const bigrams = (s: string) => {
    const out = new Set<string>();
    for (let i = 0; i < s.length - 1; i++) out.add(s.slice(i, i + 2));
    return out;
  };
  const A = bigrams(a);
  const B = bigrams(b);
  if (A.size === 0 || B.size === 0) return a === b ? 1 : 0;
  let overlap = 0;
  for (const g of A) if (B.has(g)) overlap++;
  return (2 * overlap) / (A.size + B.size);
}

function findDuplicate(
  candidate: NormalizedEvent,
  pool: ExistingCandidate[],
): { match: ExistingCandidate; confidence: number } | null {
  const candName = normalizeName(candidate.name);
  let best: { match: ExistingCandidate; confidence: number } | null = null;
  for (const other of pool) {
    if (candidate.startDate && other.event_date && candidate.startDate !== other.event_date) {
      continue; // different date -- not the same occurrence
    }
    const nameSim = bigramSimilarity(candName, normalizeName(other.name));
    let venueMatch = false;
    if (candidate.venueName && other.venue_name) {
      venueMatch = normalizeName(candidate.venueName) === normalizeName(other.venue_name);
    } else if (
      candidate.latitude != null && candidate.longitude != null &&
      other.latitude != null && other.longitude != null
    ) {
      venueMatch = haversineMeters(
        candidate.latitude, candidate.longitude, other.latitude, other.longitude,
      ) < 300;
    }
    let confidence = nameSim * 0.7 + (venueMatch ? 0.3 : 0);
    if (nameSim > 0.92 && !candidate.startDate) confidence = Math.max(confidence, nameSim * 0.85);
    if (!best || confidence > best.confidence) best = { match: other, confidence };
  }
  return best && best.confidence >= 0.55 ? best : null;
}

// ---------------------------------------------------------------------------
// Source connectors. Each returns normalized events for ONE source; adding
// a source means adding one entry here (and a matching `event_sources` row)
// -- nothing else in this file changes.
// ---------------------------------------------------------------------------
const TICKETMASTER_KEY = Deno.env.get("TICKETMASTER_API_KEY") ?? "";
const TICKETMASTER_URL = "https://app.ticketmaster.com/discovery/v2/events.json";
// Marion County, FL centroid -- see discover_items_provider.dart's
// _fallbackLat/_fallbackLng in the Flutter app.
const MARION_CENTER_LAT = 29.1872;
const MARION_CENTER_LNG = -82.1401;
const SEARCH_RADIUS_MILES = 40; // over-fetch; verifyMarionCounty() is the real filter

function mapTicketmasterClassification(
  segment?: string,
  genre?: string,
): { category: string; interestTags: string[] } {
  const seg = (segment ?? "").toLowerCase();
  const gen = (genre ?? "").toLowerCase();
  if (seg === "music") return { category: segment!, interestTags: ["live_music", "nightlife"] };
  if (seg === "arts & theatre") {
    return { category: segment!, interestTags: ["arts_culture", "family"] };
  }
  if (seg === "family") return { category: segment!, interestTags: ["family", "kids"] };
  if (seg === "film") return { category: segment!, interestTags: ["arts_culture"] };
  if (seg === "sports") return { category: segment!, interestTags: ["adventure", "family"] };
  if (gen.includes("fair") || gen.includes("festival") || gen.includes("rodeo")) {
    return { category: genre ?? "Festival", interestTags: ["festivals", "local_events"] };
  }
  return { category: segment ?? genre ?? "Event", interestTags: ["local_events"] };
}
function bestTicketmasterImage(
  images?: { url: string; width?: number; ratio?: string }[],
): string | null {
  if (!images || images.length === 0) return null;
  const wide = images.find((i) => i.ratio === "16_9" && (i.width ?? 0) >= 640);
  return (wide ?? images[0]).url ?? null;
}
function formatTicketmasterCost(
  ranges?: { min?: number; max?: number; currency?: string }[],
): string | null {
  const r = ranges?.[0];
  if (!r || r.min == null) return null;
  const cur = r.currency === "USD" ? "$" : `${r.currency ?? ""} `;
  if (r.max != null && r.max !== r.min) return `${cur}${r.min}–${cur}${r.max}`;
  return `${cur}${r.min}`;
}

async function connectTicketmaster(): Promise<NormalizedEvent[]> {
  if (!TICKETMASTER_KEY) throw new Error("TICKETMASTER_API_KEY not set");
  const out: NormalizedEvent[] = [];
  const maxPages = 5;
  for (let page = 0; page < maxPages; page++) {
    const params = new URLSearchParams({
      apikey: TICKETMASTER_KEY,
      latlong: `${MARION_CENTER_LAT},${MARION_CENTER_LNG}`,
      radius: String(SEARCH_RADIUS_MILES),
      unit: "miles",
      size: "200",
      page: String(page),
      sort: "date,asc",
    });
    const r = await fetch(`${TICKETMASTER_URL}?${params.toString()}`);
    if (!r.ok) {
      if (r.status === 404) break;
      throw new Error(`Ticketmaster ${r.status}: ${(await r.text()).slice(0, 300)}`);
    }
    const data = await r.json();
    const events: any[] = data?._embedded?.events ?? [];
    for (const ev of events) {
      const venue = ev._embedded?.venues?.[0];
      const lat = venue?.location?.latitude ? Number(venue.location.latitude) : null;
      const lng = venue?.location?.longitude ? Number(venue.location.longitude) : null;
      const cls = ev.classifications?.[0];
      const { category, interestTags } = mapTicketmasterClassification(
        cls?.segment?.name,
        cls?.genre?.name,
      );
      out.push({
        sourceEventId: ev.id,
        sourceUrl: ev.url ?? null,
        name: ev.name,
        description: ev.info ?? ev.pleaseNote ?? null,
        startDate: ev.dates?.start?.localDate ?? null,
        startTime: ev.dates?.start?.localTime ?? null,
        venueName: venue?.name ?? null,
        address: venue?.address?.line1 ?? null,
        city: venue?.city?.name ?? null,
        latitude: lat, longitude: lng,
        ticketUrl: ev.url ?? null,
        imageUrl: bestTicketmasterImage(ev.images),
        costInfo: formatTicketmasterCost(ev.priceRanges),
        contact: null,
        organizer: null,
        category, interestTags,
        raw: ev,
      });
    }
    const totalPages = data?.page?.totalPages ?? 1;
    if (page + 1 >= totalPages) break;
  }
  return out;
}

const SOURCE_CONNECTORS: Record<string, () => Promise<NormalizedEvent[]>> = {
  ticketmaster: connectTicketmaster,
  // Additional sources plug in here once they have a real, legitimately
  // accessible feed. As of this writing, ocalamarion.com (Visitors Bureau),
  // marionfl.org (county government), and ocalafl.gov (City of Ocala) expose
  // no RSS/iCal/JSON feed and the two government sites actively block
  // automated requests (HTTP 403) -- see their `event_sources` rows below
  // for the disclosed reason. Do not scrape around a site telling you not
  // to automate it.
};

// ---------------------------------------------------------------------------
// Engine
// ---------------------------------------------------------------------------
interface SourceRunResult {
  sourceKey: string;
  sourceName: string;
  discovered: number;
  new: number;
  duplicates: number;
  needsReview: number;
  rejected: number;
  published: number;
  error: string | null;
  // Diagnostic only -- populated in BOTH dry-run and live modes so a new
  // source's rejection pattern can be sanity-checked without needing a
  // live run first (e.g. "outside_marion_county (Alachua)" x40 tells you
  // the radius is fine and the county filter is doing its job, vs "expired"
  // x40 which would point at a real bug).
  rejectionReasons: Record<string, number>;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Only POST supported" }, 405);
  if (!SERVICE_KEY) return json({ error: "SUPABASE_SERVICE_ROLE_KEY not set" }, 500);

  let body: { dryRun?: boolean; sourceKeys?: string[] } = {};
  try {
    const text = await req.text();
    if (text.trim()) body = JSON.parse(text);
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }
  const dryRun = body.dryRun !== false; // default true -- safest option

  try {
    const allSources = await sbGet("event_sources?select=*");
    const requested = new Set((body.sourceKeys ?? []).map((s) => s.toLowerCase()));
    const targets = allSources.filter((s: any) =>
      s.enabled && (requested.size === 0 || requested.has(s.source_key))
    );

    if (targets.length === 0) {
      return json({ dryRun, results: [], note: "No enabled/matching sources to run." });
    }

    const results: SourceRunResult[] = [];

    for (const source of targets) {
      const connector = SOURCE_CONNECTORS[source.source_key];
      const result: SourceRunResult = {
        sourceKey: source.source_key,
        sourceName: source.name,
        discovered: 0, new: 0, duplicates: 0, needsReview: 0, rejected: 0, published: 0,
        error: null,
        rejectionReasons: {},
      };
      const tallyRejection = (reason: string) => {
        result.rejectionReasons[reason] = (result.rejectionReasons[reason] ?? 0) + 1;
      };

      if (!connector) {
        result.error = "No automated connector implemented for this source.";
        results.push(result);
        continue;
      }

      try {
        const candidates = await connector();
        result.discovered = candidates.length;

        // Existing published events (recent + upcoming only -- no need to
        // dedupe against events from a year ago) + already-discovered rows
        // for ANY source, so the same concert found via two different
        // sources still collapses to one review item.
        const existingEvents: ExistingCandidate[] = (await sbGet(
          "events?select=id,name,event_date,latitude,longitude,city&event_date=gte." +
            new Date(Date.now() - 7 * 86400000).toISOString().slice(0, 10),
        )).map((e: any) => ({ ...e, venue_name: null }));
        const existingDiscovered: ExistingCandidate[] = (await sbGet(
          "discovered_events?select=id,name,start_date,latitude,longitude,venue_name,city" +
            "&status=neq.rejected",
        )).map((e: any) => ({
          id: e.id, name: e.name, event_date: e.start_date,
          latitude: e.latitude, longitude: e.longitude, venue_name: e.venue_name, city: e.city,
        }));

        for (const candidate of candidates) {
          const today = new Date().toISOString().slice(0, 10);
          if (candidate.startDate && candidate.startDate < today) {
            result.rejected++;
            tallyRejection("expired");
            if (!dryRun) {
              await writeDiscovered(source.id, candidate, "rejected", "expired", null, null, null);
            }
            continue;
          }

          const location = await verifyMarionCounty(candidate);
          if (location.verdict === "confirmed_other_county") {
            result.rejected++;
            tallyRejection(`outside_marion_county (${location.county})`);
            if (!dryRun) {
              await writeDiscovered(
                source.id, candidate, "rejected",
                `outside_marion_county (${location.county})`, null, null, null,
              );
            }
            continue;
          }

          const dupInEvents = findDuplicate(candidate, existingEvents);
          const dupInDiscovered = !dupInEvents
            ? findDuplicate(candidate, existingDiscovered)
            : null;
          const dup = dupInEvents ?? dupInDiscovered;

          if (dup && dup.confidence >= 0.75) {
            result.duplicates++;
            if (!dryRun) {
              await writeDiscovered(
                source.id, candidate, "duplicate", null,
                dup.confidence, dupInEvents ? dup.match.id : null,
                dupInDiscovered ? dup.match.id : null,
              );
            }
            continue;
          }

          const needsReview = location.verdict === "uncertain" ||
            !candidate.startDate ||
            (!candidate.venueName && !candidate.address && candidate.latitude == null) ||
            (dup != null); // a soft/uncertain match -- let a human decide

          if (needsReview) {
            result.needsReview++;
            if (!dryRun) {
              await writeDiscovered(
                source.id, candidate, "needs_review", null,
                dup?.confidence ?? null, null, dupInDiscovered ? dup!.match.id : null,
              );
            }
            continue;
          }

          result.new++;
          if (!dryRun) {
            const row = await writeDiscovered(source.id, candidate, "verified", null, null, null, null);
            if (source.auto_publish && row) {
              const publishedId = await publishToEvents(candidate, source.source_key);
              await sbPatch(`discovered_events?id=eq.${row.id}`, {
                status: "published", published_event_id: publishedId,
              });
              result.published++;
            }
          }
        }

        if (!dryRun) {
          await sbPatch(`event_sources?id=eq.${source.id}`, {
            last_checked_at: new Date().toISOString(),
            last_success_at: new Date().toISOString(),
            last_error: null,
            last_run_discovered: result.discovered,
            last_run_new: result.new,
            last_run_duplicates: result.duplicates,
            last_run_needs_review: result.needsReview,
            last_run_rejected: result.rejected,
            updated_at: new Date().toISOString(),
          });
        }
      } catch (err) {
        result.error = String((err as Error)?.message ?? err);
        if (!dryRun) {
          await sbPatch(`event_sources?id=eq.${source.id}`, {
            last_checked_at: new Date().toISOString(),
            last_error: result.error,
            updated_at: new Date().toISOString(),
          });
        }
      }
      results.push(result);
    }

    return json({ dryRun, results });
  } catch (err) {
    console.error("marion-event-discovery error", err);
    return json(
      { error: "internal_server_error", detail: String((err as Error)?.message ?? err) },
      500,
    );
  }
});

async function writeDiscovered(
  sourceId: string,
  ev: NormalizedEvent,
  status: string,
  rejectionReason: string | null,
  matchConfidence: number | null,
  duplicateOfEventId: string | null,
  duplicateOfDiscoveredId: string | null,
): Promise<{ id: string } | null> {
  const rawCounty = ev.latitude != null && ev.longitude != null
    ? await resolveCountyByCoords(ev.latitude, ev.longitude)
    : null;
  const resolvedCounty = rawCounty ? stripCountySuffix(rawCounty) : null;

  const row = {
    source_id: sourceId,
    source_event_id: ev.sourceEventId ?? null,
    source_url: ev.sourceUrl ?? null,
    status,
    rejection_reason: rejectionReason,
    duplicate_of_event_id: duplicateOfEventId,
    duplicate_of_discovered_id: duplicateOfDiscoveredId,
    match_confidence: matchConfidence,
    name: ev.name,
    description: ev.description ?? null,
    start_date: ev.startDate ?? null,
    end_date: ev.endDate ?? null,
    start_time: ev.startTime ?? null,
    end_time: ev.endTime ?? null,
    venue_name: ev.venueName ?? null,
    address: ev.address ?? null,
    city: ev.city ?? null,
    zip: ev.zip ?? null,
    latitude: ev.latitude ?? null,
    longitude: ev.longitude ?? null,
    county: resolvedCounty,
    website: ev.website ?? null,
    ticket_url: ev.ticketUrl ?? null,
    image_url: ev.imageUrl ?? null,
    organizer: ev.organizer ?? null,
    contact: ev.contact ?? null,
    cost_info: ev.costInfo ?? null,
    category: ev.category ?? null,
    interest_tags: ev.interestTags ?? [],
    raw_payload: ev.raw ?? null,
    updated_at: new Date().toISOString(),
  };
  const result = await sbUpsert(
    "discovered_events?on_conflict=source_id,source_event_id",
    row,
    "resolution=merge-duplicates,return=representation",
  );
  return Array.isArray(result) ? result[0] : result;
}

async function publishToEvents(ev: NormalizedEvent, sourceKey: string): Promise<string | null> {
  const row = {
    name: ev.name,
    description: ev.description ?? null,
    image_url: ev.imageUrl ?? null,
    latitude: ev.latitude ?? null,
    longitude: ev.longitude ?? null,
    county: "Marion",
    city: ev.city ?? null,
    event_date: ev.startDate ?? null,
    start_time: ev.startTime ?? null,
    end_time: ev.endTime ?? null,
    external_website: ev.website ?? null,
    ticket_url: ev.ticketUrl ?? null,
    cost_info: ev.costInfo ?? null,
    category: ev.category ?? null,
    interest_tags: ev.interestTags ?? [],
    active: true,
    source: sourceKey,
    source_id: ev.sourceEventId ?? null,
  };
  const result = await sbUpsert(
    "events?on_conflict=source,source_id",
    row,
    "resolution=merge-duplicates,return=representation",
  );
  const first = Array.isArray(result) ? result[0] : result;
  return first?.id ?? null;
}
