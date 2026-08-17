-- ExplorerOS — Master Geographic Import & AI Content Pipeline, Phase 1.
--
-- Scalable foundation for importing every location in the United States on the
-- ONE existing `locations` table (no parallel system):
--   • parent_location_id  — self-referencing hierarchy, unlimited depth
--                           (Country → State → County → City → Park → POI …),
--                           with parent-narration resume support in the engine.
--   • phone               — the last missing PoI contact field.
--   • discoverable / background_detection — per-location GPS behavior flags.
--   • UNIQUE (source, source_id) — the dedupe key every importer upserts on
--                           ("detect duplicates / update existing / only missing").
--   • geo/hierarchy/status indexes — fast nationwide nearby + scoped queries at
--                           millions-of-rows scale (bounding-box friendly; a
--                           PostGIS/earthdistance upgrade can layer on later).
--   • seeds the additional US location categories into the admin-managed
--     `categories` table (migration 0039), mirroring the Dart LocationType enum.
--
-- Additive only. Idempotent: safe to re-run.

alter table public.locations
  add column if not exists parent_location_id  uuid references public.locations(id) on delete set null,
  add column if not exists phone                text,
  add column if not exists discoverable         boolean not null default true,
  add column if not exists background_detection boolean not null default true;

-- Dedupe / upsert key for importers. Partial so manually-created rows (no
-- source) are never blocked. Two rows with the same (source, source_id) can't
-- coexist → importers UPSERT instead of duplicating.
create unique index if not exists locations_source_uidx
  on public.locations (source, source_id)
  where source is not null and source_id is not null;

create index if not exists locations_parent_idx
  on public.locations (parent_location_id);
create index if not exists locations_latlng_idx
  on public.locations (latitude, longitude);
create index if not exists locations_state_county_city_idx
  on public.locations (state, county, city);

-- Additional US location categories (admin-manageable list from 0039). The
-- built-in taxonomy stays; these extend it so the importer can classify every
-- US feature type. sort_order continues after the 'area' seed (28).
insert into public.categories (slug, label, sort_order) values
  ('country', 'Country', 29),
  ('state', 'State', 30),
  ('town', 'Town', 31),
  ('village', 'Village', 32),
  ('neighborhood', 'Neighborhood', 33),
  ('city_park', 'City Park', 34),
  ('national_forest', 'National Forest', 35),
  ('state_forest', 'State Forest', 36),
  ('wildlife_management_area', 'Wildlife Management Area', 37),
  ('waterfall', 'Waterfall', 38),
  ('beach', 'Beach', 39),
  ('monument', 'Monument', 40),
  ('memorial', 'Memorial', 41),
  ('lighthouse', 'Lighthouse', 42),
  ('bridge', 'Bridge', 43),
  ('cave', 'Cave', 44),
  ('business', 'Business', 45),
  ('coffee_shop', 'Coffee Shop', 46),
  ('festival_grounds', 'Festival Grounds', 47),
  ('event_venue', 'Event Venue', 48),
  ('local_attraction', 'Local Attraction', 49)
on conflict (lower(slug)) do nothing;
