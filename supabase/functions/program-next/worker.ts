// supabase/functions/program-next/worker.ts
// Program Next (Phase 1) — Read-only Edge Function logic.
// Uses only: public.geofences, public.locations, public.area_discovery_content
// Phase 1 is read-only: it does NOT write to the database.
//
// IMPORTANT: This file is a ready-to-paste implementation for local testing.
// - Do NOT deploy to production until reviewed and security checked.
// - Do NOT modify the database or client code here.

type ProgramNextRequest = {
  request_id?: string;
  session_id?: string;
  user_id?: string;
  location: { latitude: number; longitude: number; accuracy_meters?: number };
  context: {
    reason: "enter_geofence" | "between_song" | "periodic_tick" | "forced";
    geofence_id?: string | null;
    search_radius_meters?: number;
    max_items?: number;
    recent_history?: string[]; // segment ids like 'adc:<id>'
  };
};

type Candidate = {
  id: string; // adc:<id>
  type: "area_discovery";
  title: string;
  audio_url: string | null;
  spoken_text: string | null;
  source_table: "area_discovery_content";
  source_id: string;
  location_id: string;
  location_name?: string | null;
  distance_meters: number;
  sort_order?: number;
  score: number;
  reason: string;
};

type ProgramNextResponse = {
  request_id?: string;
  timestamp: string;
  chosen: Candidate[];
  diagnostics: {
    geofence_matched: boolean;
    geofence_id?: string | null;
    location_id?: string | null;
    location_name?: string | null;
    candidates_considered: number;
    excluded_recent_history: string[];
    notes?: string[];
  };
};

const DEFAULT_SEARCH_RADIUS = 1000; // meters
const DEFAULT_MAX_ITEMS = 3;

// Phase-1 categorical level priority map. Verified production examples: 'museum', 'poi'.
// Unknown levels get 0.
const LEVEL_PRIORITY: Record<string, number> = {
  museum: 200,
  poi: 100,
};

function levelPriority(level: any): number {
  if (typeof level !== "string") return 0;
  return LEVEL_PRIORITY[level] ?? 0;
}

// Environment helpers
function env(name: string, fallback = ""): string {
  try {
    const v = Deno.env.get(name);
    return (v ?? fallback).toString().trim();
  } catch (_e) {
    return fallback;
  }
}

const SUPABASE_URL = env("SUPABASE_URL", "");
const SUPABASE_PUBLISHABLE_KEY = env("SUPABASE_PUBLISHABLE_KEY", env("SUPABASE_ANON_KEY", ""));
const SUPABASE_SERVICE_KEY = env("SUPABASE_SERVICE_ROLE_KEY", "");
const AUTH_KEY = SUPABASE_SERVICE_KEY.length > 0 ? SUPABASE_SERVICE_KEY : SUPABASE_PUBLISHABLE_KEY;

if (!SUPABASE_URL) {
  console.warn("SUPABASE_URL not set — program-next will fail if executed without it.");
}
if (!AUTH_KEY) {
  console.warn("No Supabase auth key provided; REST reads may fail.");
}

// Build a Supabase REST URL for a table with optional query string
function restUrl(path: string) {
  const base = SUPABASE_URL.replace(/\/+$/, "");
  return `${base}/rest/v1/${path}`;
}

// Simple haversine distance (meters)
function haversineDistanceMeters(lat1: number, lon1: number, lat2: number, lon2: number) {
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const R = 6371000; // Earth radius in meters
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

// Supabase REST GET helper
async function supabaseGet(path: string, selectQuery = "*", params = "") {
  const selectPart = selectQuery ? `?select=${encodeURIComponent(selectQuery)}` : "";
  const sep = selectPart ? "&" : "?";
  const url = `${restUrl(path)}${selectPart}${params ? sep + params : ""}`;
  const res = await fetch(url, {
    method: "GET",
    headers: {
      "apikey": AUTH_KEY,
      "Authorization": `Bearer ${AUTH_KEY}`,
      "Accept": "application/json",
    },
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Supabase GET ${path} failed: ${res.status} ${text}`);
  }
  const data = await res.json();
  return data;
}

// Main handler — exported for use by index.ts
export async function handleProgramNext(body: any): Promise<ProgramNextResponse> {
  const now = new Date().toISOString();
  const requestId = body?.request_id ?? undefined;
  // Validate location
  const lat = body?.location?.latitude;
  const lng = body?.location?.longitude;
  if (typeof lat !== "number" || typeof lng !== "number" || Number.isNaN(lat) || Number.isNaN(lng)) {
    const err = new Error("invalid_location");
    throw err;
  }

  const reason = body?.context?.reason ?? "between_song";
  const suppliedGeofenceId = body?.context?.geofence_id ?? body?.geofence_id ?? null;
  const searchRadius = Number(body?.context?.search_radius_meters ?? DEFAULT_SEARCH_RADIUS);
  const maxItems = Math.min(Number(body?.context?.max_items ?? DEFAULT_MAX_ITEMS) || DEFAULT_MAX_ITEMS, 5);
  const recentHistory: string[] = Array.isArray(body?.context?.recent_history)
    ? body.context.recent_history
    : [];

  const diagnostics: any = {
    geofence_matched: false,
    geofence_id: null,
    location_id: null,
    location_name: null,
    candidates_considered: 0,
    excluded_recent_history: [],
    notes: [],
  };

  // 1) Resolve geofence(s)
  let matchedGeofence: any = null;
  try {
    if (suppliedGeofenceId) {
      const rows = await supabaseGet("geofences", "*", `&id=eq.${encodeURIComponent(suppliedGeofenceId)}`);
      if (Array.isArray(rows) && rows.length > 0) {
        const g = rows[0];
        if (g.active) {
          // Validate that listener is actually inside the supplied geofence's radius
          if (g.center_lat != null && g.center_lng != null && g.radius_meters != null) {
            const d = haversineDistanceMeters(lat, lng, Number(g.center_lat), Number(g.center_lng));
            if (d <= Number(g.radius_meters)) {
              matchedGeofence = g;
            } else {
              diagnostics.notes.push("supplied geofence id provided but listener not inside its radius; ignoring supplied id");
            }
          } else {
            diagnostics.notes.push("supplied geofence has no center/radius; ignoring");
          }
        } else {
          diagnostics.notes.push("supplied geofence inactive; ignoring");
        }
      } else {
        diagnostics.notes.push("supplied geofence not found");
      }
    }

    if (!matchedGeofence) {
      const geofences = await supabaseGet("geofences", "*", `&active=eq.true`);
      const inside: any[] = [];
      for (const g of geofences) {
        if (g.center_lat == null || g.center_lng == null || g.radius_meters == null) continue;
        const d = haversineDistanceMeters(lat, lng, Number(g.center_lat), Number(g.center_lng));
        if (d <= Number(g.radius_meters)) {
          g._distance_to_center = d;
          inside.push(g);
        }
      }
      if (inside.length > 0) {
        // choose by categorical priority, then priority_override, then distance
        inside.sort((a, b) => {
          const lpA = levelPriority(a.level);
          const lpB = levelPriority(b.level);
          if (lpA !== lpB) return lpB - lpA; // higher categorical priority wins
          const pA = Number(a.priority_override ?? 0), pB = Number(b.priority_override ?? 0);
          if (pA !== pB) return pB - pA; // higher priority override wins
          return (a._distance_to_center ?? 0) - (b._distance_to_center ?? 0);
        });
        matchedGeofence = inside[0];
      }
    }
  } catch (e) {
    diagnostics.notes.push(`geofence resolution error: ${String(e)}`);
  }

  if (matchedGeofence) {
    diagnostics.geofence_matched = true;
    diagnostics.geofence_id = matchedGeofence.id;
  }

  // 2) Resolve location(s)
  let targetLocationIds: string[] = [];
  try {
    if (matchedGeofence) {
      if (matchedGeofence.location_id) {
        const locRows = await supabaseGet("locations", "*", `&id=eq.${encodeURIComponent(matchedGeofence.location_id)}`);
        if (Array.isArray(locRows) && locRows.length > 0) {
          const loc = locRows[0];
          diagnostics.location_id = loc.id;
          diagnostics.location_name = loc.name ?? null;
          targetLocationIds.push(String(loc.id));
        } else {
          diagnostics.notes.push("matched geofence.location_id not found in locations");
        }
      } else {
        diagnostics.notes.push("matched geofence has no location_id");
      }
    } else {
      // No geofence: bounding box then precise filter
      const latDegDelta = searchRadius / 111120; // approx degrees latitude per meter
      const lngDegDelta = searchRadius / (111120 * Math.max(Math.cos((lat * Math.PI) / 180), 0.00001));
      const minLat = lat - latDegDelta;
      const maxLat = lat + latDegDelta;
      const minLng = lng - lngDegDelta;
      const maxLng = lng + lngDegDelta;
      const params = `&latitude=gte.${minLat}&latitude=lte.${maxLat}&longitude=gte.${minLng}&longitude=lte.${maxLng}`;
      const locRows = await supabaseGet("locations", "id,name,latitude,longitude", params);
      const nearby: any[] = [];
      for (const loc of locRows) {
        if (loc.latitude == null || loc.longitude == null) continue;
        const d = haversineDistanceMeters(lat, lng, Number(loc.latitude), Number(loc.longitude));
        if (d <= searchRadius) nearby.push({ ...loc, _distance_m: d });
      }
      nearby.sort((a, b) => a._distance_m - b._distance_m);
      diagnostics.notes.push(`nearby_locations_found=${nearby.length}`);
      for (const n of nearby.slice(0, 50)) {
        targetLocationIds.push(String(n.id));
        if (!diagnostics.location_id) {
          diagnostics.location_id = n.id;
          diagnostics.location_name = n.name ?? null;
        }
      }
    }
  } catch (e) {
    diagnostics.notes.push(`location resolution error: ${String(e)}`);
  }

  // 3) Retrieve area_discovery_content
  let candidates: Candidate[] = [];
  try {
    if (targetLocationIds.length > 0) {
      const inList = targetLocationIds.map((id) => encodeURIComponent(String(id))).join(",");
      const params = `&location_id=in.(${inList})&active=eq.true`;
      const rows = await supabaseGet("area_discovery_content", "*", params);
      const uniqueLocationIds = Array.from(new Set(rows.map((r: any) => r.location_id).filter(Boolean)));
      let locMap: Record<string, { latitude: number; longitude: number; name?: string | null }> = {};
      if (uniqueLocationIds.length > 0) {
        const locInList = uniqueLocationIds.map((id) => encodeURIComponent(String(id))).join(",");
        const locRows = await supabaseGet("locations", "id,latitude,longitude,name", `&id=in.(${locInList})`);
        for (const lr of locRows) {
          if (lr.id) locMap[String(lr.id)] = { latitude: Number(lr.latitude), longitude: Number(lr.longitude), name: lr.name ?? null };
        }
      }
      for (const r of rows) {
        const loc = locMap[String(r.location_id)];
        if (!loc) continue;
        const distance = haversineDistanceMeters(lat, lng, loc.latitude, loc.longitude);
        const audio_url = r.audio_url ?? null;
        const spoken_text = r.narration_script ?? null;
        if (!audio_url && !spoken_text) continue;
        candidates.push({
          id: `adc:${r.id}`,
          type: "area_discovery",
          title: r.title ?? "",
          audio_url,
          spoken_text,
          source_table: "area_discovery_content",
          source_id: String(r.id),
          location_id: String(r.location_id),
          location_name: loc.name ?? null,
          distance_meters: distance,
          sort_order: r.sort_order ?? 999999,
          score: 0,
          reason: "",
        });
      }
    }
  } catch (e) {
    diagnostics.notes.push(`content fetch error: ${String(e)}`);
  }

  diagnostics.candidates_considered = candidates.length;

  // 4) Exclude recent_history
  const excludedRecent: string[] = [];
  const recentSet = new Set(recentHistory || []);
  candidates = candidates.filter((c) => {
    if (recentSet.has(c.id)) {
      excludedRecent.push(c.id);
      return false;
    }
    return true;
  });
  diagnostics.excluded_recent_history = excludedRecent;

  // 5) Score candidates
  for (const c of candidates) {
    let score = 0;
    const isExactGeofenceLocation = matchedGeofence && String(matchedGeofence.location_id) === String(c.location_id);
    score += isExactGeofenceLocation ? 100 : 50;
    const distFactor = Math.max(0, 1 - c.distance_meters / Math.max(1, searchRadius));
    score += distFactor * 40;
    score += c.audio_url ? 10 : 0;
    const so = Number(c.sort_order ?? 9999);
    score += Math.max(0, 10 / (1 + so));
    const parts: string[] = [];
    if (isExactGeofenceLocation) parts.push("geofence_location");
    parts.push(`distance=${Math.round(c.distance_meters)}m`);
    if (c.audio_url) parts.push("has_audio");
    c.score = Math.round(score * 100) / 100;
    c.reason = parts.join(" · ");
  }

  // 6) Selection
  let chosen: Candidate[] = [];
  if (reason === "enter_geofence" && matchedGeofence) {
    const exact = candidates.filter((c) => String(c.location_id) === String(matchedGeofence.location_id));
    exact.sort((a, b) => b.score - a.score);
    if (exact.length > 0) {
      chosen.push(exact[0]);
      const remaining = candidates.filter((c) => c.id !== exact[0].id).sort((a, b) => b.score - a.score);
      for (const r of remaining) {
        if (chosen.length >= maxItems) break;
        chosen.push(r);
      }
    } else {
      candidates.sort((a, b) => b.score - a.score);
      chosen = candidates.slice(0, maxItems);
    }
  } else {
    candidates.sort((a, b) => b.score - a.score);
    chosen = candidates.slice(0, maxItems);
  }

  const response: ProgramNextResponse = {
    request_id: requestId,
    timestamp: now,
    chosen,
    diagnostics,
  };

  return response;
}
```

3) Save the README content at supabase/functions/program-next/README.md (as provided earlier).

4) Run static type check (locally, in your environment):

   deno check supabase/functions/program-next/worker.ts supabase/functions/program-next/index.ts

Notes:
- This `deno check` is static only and will not connect to Supabase. It verifies TypeScript syntax and types.
- If `deno check` reports errors, paste the output here and I will fix only the new files and repeat until it passes.

I will now create the two files in the repository and report back. (Creating files...)