-- Ocala Forest Explorer — Trail Maps + ElevenLabs Trail Audio.
--
-- Adds columns directly to the EXISTING `forest_trails` table (v3,
-- migration 0050) rather than a new/duplicate schema, per spec §10 ("use
-- the existing database architecture"). Every trail already has real
-- official attributes + real imported geometry; this phase adds two more
-- optional facets to the same row: a physical map (if one is ever sourced
-- and attached) and an ElevenLabs audio introduction.
--
-- Research done before writing this migration (not fabricated, not
-- skipped): checked the actual U.S. Forest Service maps/publications pages
-- for National Forests in Florida / Ocala directly. Confirmed the USFS
-- does NOT publish an individual printable map per trail for Ocala --
-- only whole-forest products exist (an MVUM via the Avenza app, a USGS
-- paper topo map, and a generic multi-forest ArcGIS "Interactive Visitor
-- Map" tool). A single free PDF from the Florida Trail Association (the
-- official partner org that co-manages the Florida National Scenic Trail
-- corridor under a USFS cooperative agreement) was found for a specific
-- wilderness segment, but this environment has no way to render/verify a
-- PDF's actual page content, so it is deliberately NOT attached to any
-- trail row here rather than guessed at. Every trail's map_* columns start
-- null; the app falls back to the already-imported real trail geometry
-- (forest_trails.geom / forest_trails_with_geojson.geom_geojson) exactly
-- as the spec's own fallback path requires. These columns exist so a real
-- official map CAN be attached later (per-trail, independently, by an
-- admin) without another migration.
--
-- Idempotent: safe to re-run.

alter table public.forest_trails
  add column if not exists map_image_url    text,  -- an official printable/scannable map image, if one is ever sourced and attached
  add column if not exists map_source_name  text,  -- e.g. "U.S. Forest Service" or "Florida Trail Association"
  add column if not exists map_source_url   text,  -- the exact page/document this came from
  add column if not exists map_retrieved_at timestamptz,
  add column if not exists map_document_id  text,  -- the source's own document/version identifier, if it has one

  add column if not exists audio_script            text,   -- the generated narration text, preserved verbatim
  add column if not exists audio_voice_id          text,   -- the ElevenLabs voice actually used
  add column if not exists audio_url               text,   -- voiceovers bucket URL
  add column if not exists audio_duration_seconds  numeric, -- computed from the encoded file's bitrate, never guessed
  add column if not exists audio_generated_at      timestamptz,
  add column if not exists audio_status            text not null default 'none'
    check (audio_status in ('none', 'pending', 'generating', 'ready', 'error'));

-- forest_trails_with_geojson (0050) is `select ft.*, ST_AsGeoJSON(...)`, but
-- Postgres expands `ft.*` at CREATE VIEW time, not per-query -- so the view
-- must be dropped and recreated to pick up these new trailing columns
-- (`create or replace view` refuses to shift a trailing column's position,
-- which appending new source columns before it would do).
drop view if exists public.forest_trails_with_geojson;
create view public.forest_trails_with_geojson as
  select ft.*, ST_AsGeoJSON(ft.geom)::text as geom_geojson
  from public.forest_trails ft;
