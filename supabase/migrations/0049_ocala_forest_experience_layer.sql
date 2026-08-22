-- Ocala Forest Explorer v2 — the Experience layer.
--
-- Extends forest_locations (never touching any other table) with the
-- fields needed for GPS/geofence-triggered contextual experiences:
--   experience_type — which primary experience (Trails / Discoveries /
--     Forest Stories) a location belongs to.
--   story_category  — free-form grouping for Forest Stories, mirroring
--     StoryCategory's tokens conceptually without a hard dependency on the
--     Marion story system.
--   qr_code_id      — reserved for future QR-code trail stops. Unused
--     today; nothing reads or writes it yet.
--   trigger_type    — reserved for future non-geofence triggers (e.g.
--     'qr_code'). Only 'geofence' is implemented today.
--
-- Idempotent: safe to re-run.

alter table public.forest_locations
  add column if not exists experience_type text not null default 'discovery',
  add column if not exists story_category text,
  add column if not exists qr_code_id text,
  add column if not exists trigger_type text not null default 'geofence';

-- Backfill: the one v1 seed row that's actually a trailhead becomes a
-- trail_stop; everything else stays at the 'discovery' default. No story
-- content is seeded — nothing is fabricated to fill that category.
update public.forest_locations
set experience_type = 'trail_stop'
where name = 'Salt Springs Trailhead' and experience_type = 'discovery';
