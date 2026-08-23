// Personalized voiced event alerts: Approved Event -> Match Against User ->
// Personalized Audio -> Deep Link -> Push Notification (payload only for
// now -- see below) -> Test With One User -> Open Event -> Hear About It.
//
// Reuses existing systems only: `events.interest_tags` (already populated
// by the event discovery engine / admin), `profiles.interests` (the same
// Discover interest picker every user already has), and `discover-narration`
// for the actual ElevenLabs voice (a new 'alert' kind added there, not a
// second audio system).
//
// Two modes, both scored the same way:
//   - Bulk (body: {eventId}) -- scores EVERY user with interests set
//     against this event and records the result in `event_matches`
//     (tier/score/matched tags only). Does NOT call OpenAI/ElevenLabs for
//     every user -- that would be wasteful generation for a channel that
//     doesn't exist yet (see below). This is the "when an event enters the
//     approved database, determine whether it's a match" step, and is what
//     powers the admin's "Potential matches / High-match users" view.
//   - Test mode (body: {eventId, testUserId}) -- runs the FULL pipeline for
//     ONE user: match -> personalized script -> ElevenLabs audio ->
//     notification title/body -> deep link, and writes an `event_matches`
//     row with status 'test'. Never sends a real push (there is no real
//     push channel configured in this project yet -- see push_devices in
//     migration 0056, an empty, unwired table reserved for when Firebase/
//     APNs credentials are provisioned).
//
// Repeat protection: a user already matched against this event (status
// beyond 'matched'/'test') is skipped on subsequent bulk runs, per
// `event_matches`'s (event_id, user_id) unique index.
//
// Deploy: supabase functions deploy event-match-and-notify
// Secrets reused (already configured): OPENAI_API_KEY, ELEVENLABS_API_KEY
// (both via discover-narration), SUPABASE_SERVICE_ROLE_KEY / SUPABASE_URL

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

// ---------------------------------------------------------------------------
// Matching -- configurable thresholds (spec: "the system should have
// configurable thresholds for notification eligibility").
// ---------------------------------------------------------------------------
const HIGH_THRESHOLD = 0.6;
const MEDIUM_THRESHOLD = 0.3;

interface MatchResult {
  tier: "high" | "medium" | "low";
  score: number;
  matched: string[];
}

function scoreMatch(eventTags: string[], userInterests: string[], eventDate: string | null): MatchResult {
  const matched = eventTags.filter((t) => userInterests.includes(t));
  if (matched.length === 0) return { tier: "low", score: 0, matched: [] };

  let score = matched.length / Math.max(eventTags.length, 1);
  if (eventDate) {
    const days = Math.floor((new Date(eventDate).getTime() - Date.now()) / 86_400_000);
    if (days >= 0 && days <= 7) score += 0.25;
    else if (days >= 0 && days <= 14) score += 0.1;
  }
  if (matched.length >= 2) score += 0.15;
  score = Math.min(score, 1.5);

  const tier = score >= HIGH_THRESHOLD ? "high" : score >= MEDIUM_THRESHOLD ? "medium" : "low";
  return { tier, score, matched };
}

// ---------------------------------------------------------------------------
// Notification copy variations (spec: "create notification variations so
// users don't receive the exact same wording every time").
// ---------------------------------------------------------------------------
const NOTIFICATION_VARIANTS: { id: string; title: string; body: (name: string | null) => string }[] = [
  {
    id: "something_you_might_like",
    title: "🎧 Something You Might Like",
    body: (name) => `${name ? `Hey ${name}, ` : ""}I found an event that matches your interests.`,
  },
  {
    id: "found_something_for_you",
    title: "🎆 I Found Something For You",
    body: () => "There's something happening I think you may enjoy.",
  },
  {
    id: "new_discovery",
    title: "⭐ New Marion County Discovery",
    body: () => "Something new just came in that looks like a good match for you.",
  },
  {
    id: "thought_of_you",
    title: "🎧 Thought You'd Want to Know",
    body: (name) => `${name ? `${name}, this` : "This"} one looks like your kind of thing.`,
  },
  {
    id: "worth_a_listen",
    title: "🌟 Worth a Listen",
    body: () => "Tap to hear why I thought of you for this one.",
  },
];

function pickVariant(): typeof NOTIFICATION_VARIANTS[number] {
  return NOTIFICATION_VARIANTS[Math.floor(Math.random() * NOTIFICATION_VARIANTS.length)];
}

// ---------------------------------------------------------------------------
// discover-narration client -- the SAME function Hear About It/Tell Me
// More/the greeting use; kind 'alert' is the only new addition (see
// discover-narration/index.ts).
// ---------------------------------------------------------------------------
async function generateAlertNarration(params: {
  eventId: string;
  userId: string;
  eventName: string;
  category: string | null;
  description: string | null;
  dateLabel: string | null;
  timeLabel: string | null;
  costLabel: string | null;
  matchedInterests: string[];
  visitorName: string | null;
}): Promise<{ text: string; audioUrl: string | null } | null> {
  try {
    const r = await fetch(buildSupabaseUrl("functions/v1/discover-narration"), {
      method: "POST",
      headers: { ...SB, "Content-Type": "application/json" },
      body: JSON.stringify({
        subjectType: "event",
        // Namespaced per-visitor -- an alert is personalized, so two
        // different visitors' scripts must never collide in the cache.
        subjectId: `${params.eventId}::${params.userId}`,
        kind: "alert",
        name: params.eventName,
        category: params.category ?? undefined,
        description: params.description ?? undefined,
        dateLabel: params.dateLabel ?? undefined,
        timeLabel: params.timeLabel ?? undefined,
        costLabel: params.costLabel ?? undefined,
        matchedInterests: params.matchedInterests,
        visitorName: params.visitorName ?? undefined,
      }),
    });
    if (!r.ok) return null;
    const data = await r.json();
    return { text: data.text ?? "", audioUrl: data.audioUrl ?? null };
  } catch {
    return null;
  }
}

interface EventRow {
  id: string;
  name: string;
  category: string | null;
  description: string | null;
  short_description: string | null;
  interest_tags: string[] | null;
  event_date: string | null;
  start_time: string | null;
  cost_info: string | null;
  active: boolean;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Only POST supported" }, 405);
  if (!SERVICE_KEY) return json({ error: "SUPABASE_SERVICE_ROLE_KEY not set" }, 500);

  let body: { eventId?: string; testUserId?: string; listUsers?: boolean } = {};
  try {
    const text = await req.text();
    if (text.trim()) body = JSON.parse(text);
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }

  // Admin test-mode picker support: `profiles` RLS is strictly
  // `auth.uid() = id` (self-only), so the admin app's own authenticated
  // session cannot list other users to populate a "Test User" dropdown --
  // only the service-role key (used here) can. This is the one place that
  // list is exposed, and only id/first_name/interests (never anything else
  // from the profile).
  if (body.listUsers) {
    const allProfiles = await sbGet("profiles?select=id,first_name,interests&order=first_name");
    const withInterests = allProfiles.filter((p: any) => (p.interests ?? []).length > 0);
    return json({
      users: withInterests.map((p: any) => ({
        id: p.id, firstName: p.first_name, interests: p.interests,
      })),
    });
  }

  if (!body.eventId) return json({ error: "eventId is required" }, 400);

  try {
    const events = await sbGet(`events?id=eq.${body.eventId}&select=*&limit=1`);
    const event = events[0] as EventRow | undefined;
    if (!event) return json({ error: "event not found" }, 404);

    const eventTags = event.interest_tags ?? [];
    const dateLabel = event.event_date
      ? new Date(event.event_date).toLocaleDateString("en-US", {
        weekday: "long", month: "long", day: "numeric",
      })
      : null;

    if (body.testUserId) {
      // ---- Test mode: full pipeline, one user, no real push. ----
      const profiles = await sbGet(
        `profiles?id=eq.${body.testUserId}&select=id,first_name,interests&limit=1`,
      );
      const profile = profiles[0];
      if (!profile) return json({ error: "test user not found" }, 404);

      const userInterests: string[] = profile.interests ?? [];
      const match = scoreMatch(eventTags, userInterests, event.event_date);

      let narration: { text: string; audioUrl: string | null } | null = null;
      let variant: typeof NOTIFICATION_VARIANTS[number] | null = null;
      if (match.matched.length > 0) {
        narration = await generateAlertNarration({
          eventId: event.id,
          userId: profile.id,
          eventName: event.name,
          category: event.category,
          description: event.description ?? event.short_description,
          dateLabel,
          timeLabel: event.start_time,
          costLabel: event.cost_info,
          matchedInterests: match.matched,
          visitorName: profile.first_name,
        });
        variant = pickVariant();
      }

      const deepLink = `/discover-event/${event.id}`;
      const row = await sbUpsert(
        "event_matches?on_conflict=event_id,user_id",
        {
          event_id: event.id,
          user_id: profile.id,
          match_tier: match.tier,
          score: match.score,
          matched_interest_tags: match.matched,
          status: "test",
          notification_variant_id: variant?.id ?? null,
          notification_title: variant?.title ?? null,
          notification_body: variant ? variant.body(profile.first_name) : null,
          narration_script: narration?.text ?? null,
          narration_audio_url: narration?.audioUrl ?? null,
        },
        "resolution=merge-duplicates,return=representation",
      );

      return json({
        mode: "test",
        event: { id: event.id, name: event.name },
        user: { id: profile.id, firstName: profile.first_name },
        match,
        notification: variant
          ? { title: variant.title, body: variant.body(profile.first_name), variantId: variant.id }
          : null,
        narration,
        deepLink,
        note: "TEST MODE — no push notification was sent.",
        savedMatchId: Array.isArray(row) ? row[0]?.id : row?.id,
      });
    }

    // ---- Bulk mode: score every interested user, generate nothing yet. ----
    // Filtered in-process (not via a PostgREST array-not-empty filter) to
    // avoid any ambiguity in how an empty-array literal needs encoding in
    // the query string -- profile counts are small enough that this costs
    // nothing meaningful.
    const allProfiles = await sbGet("profiles?select=id,first_name,interests");
    const profiles = allProfiles.filter((p: any) => (p.interests ?? []).length > 0);
    const existing = await sbGet(
      `event_matches?event_id=eq.${event.id}&select=user_id,status`,
    );
    const alreadyHandled = new Set(
      existing.filter((e: any) => e.status !== "matched").map((e: any) => e.user_id),
    );

    let potentialMatches = 0;
    let highMatchUsers = 0;
    let skippedAlreadyHandled = 0;

    for (const profile of profiles) {
      if (alreadyHandled.has(profile.id)) {
        skippedAlreadyHandled++;
        continue;
      }
      const userInterests: string[] = profile.interests ?? [];
      const match = scoreMatch(eventTags, userInterests, event.event_date);
      if (match.tier === "low") continue; // spec: low match is not recorded as a "potential match"

      potentialMatches++;
      if (match.tier === "high") highMatchUsers++;

      await sbUpsert(
        "event_matches?on_conflict=event_id,user_id",
        {
          event_id: event.id,
          user_id: profile.id,
          match_tier: match.tier,
          score: match.score,
          matched_interest_tags: match.matched,
          status: "matched",
        },
        "resolution=merge-duplicates",
      );
    }

    return json({
      mode: "bulk",
      event: { id: event.id, name: event.name },
      usersConsidered: profiles.length,
      potentialMatches,
      highMatchUsers,
      skippedAlreadyHandled,
      note: "Scored only — no notifications sent (no push channel configured yet) " +
        "and no audio pre-generated (generated on demand via test mode / when a " +
        "real send exists).",
    });
  } catch (err) {
    console.error("event-match-and-notify error", err);
    return json(
      { error: "internal_server_error", detail: String((err as Error)?.message ?? err) },
      500,
    );
  }
});
