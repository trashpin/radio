Program Next — Phase 1 (Edge Function)

Purpose
-------
Phase 1 read-only Program Next: given a listener GPS fix and context,
resolve the active geofence → location → area_discovery_content and return
up to N playable items.

Phase-1 constraints:
- Uses only these production tables: public.geofences, public.locations, public.area_discovery_content
- Read-only: does not write to the database
- Relies on client-supplied recent_history to avoid immediate repeats
- Does not change geofencing or other DB tables
- Returns diagnostics to help tuning

Environment
-----------
Set these env vars in the function runtime or locally for testing:

- SUPABASE_URL (required) e.g. https://<project>.supabase.co
- SUPABASE_PUBLISHABLE_KEY or SUPABASE_ANON_KEY (for reads)
- (Optional) SUPABASE_SERVICE_ROLE_KEY — if provided, the function will use it preferentially for reads

API
---
POST /program-next
Content-Type: application/json

Request (example):
{
  "request_id": "req-1",
  "session_id": "sess-1",
  "user_id": "user-1",
  "location": { "latitude": 29.1791, "longitude": -82.1401, "accuracy_meters": 10 },
  "context": {
    "reason": "enter_geofence",
    "geofence_id": "gf-456",
    "search_radius_meters": 1000,
    "max_items": 3,
    "recent_history": ["adc:111"]
  }
}

Response (example):
{
  "request_id": "req-1",
  "timestamp": "...",
  "chosen": [ { ...candidate objects... } ],
  "diagnostics": { ... }
}

Behavior summary
----------------
- Validate lat/lng.
- If context.geofence_id supplied: fetch it and verify listener is inside its center/radius; only then use it.
- Otherwise: fetch active geofences, test containment, choose best by categorical level priority, priority_override, distance.
- Determine location_id(s) from geofence or nearby locations.
- Fetch active area_discovery_content for those locations; require audio_url OR narration_script.
- Exclude items present in recent_history (client-supplied).
- Score candidates by geofence relevance, distance, audio presence, and sort_order.
- For enter_geofence: strongly prefer matched-location items; return at most one primary item followed by up to (max_items-1) more.
- For between_song/periodic_tick: return up to max_items, preferring closer/available-audio items.
- Return diagnostics: matched geofence/location, candidate counts, excluded items, notes.

Phase 1 notes
------------
- There is NO duration-based selection in Phase 1 — area_discovery_content does not contain duration_seconds in the verified schema.
- The function is intentionally read-only and minimal to prove the core loop.

Local testing
-------------
1) Set environment variables in your shell:
   export SUPABASE_URL=https://<project>.supabase.co
   export SUPABASE_PUBLISHABLE_KEY=sb_publishable_xxx
   # or: export SUPABASE_SERVICE_ROLE_KEY=sb_secret_xxx (preferred for server-side reads)

2) Type-check with Deno:
   deno check supabase/functions/program-next/worker.ts supabase/functions/program-next/index.ts

3) Run locally (Deno):
   deno run --allow-net --allow-env supabase/functions/program-next/index.ts

4) Submit a test POST (curl):
   curl -X POST 'http://localhost:8000' -H 'Content-Type: application/json' -d @test_request.json

Security
--------
- Do not embed service-role keys in client applications.
- Protect function invocation with your preferred auth (function-level secret, signed requests, or Supabase auth).
