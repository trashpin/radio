-- Ocala Forest Explorer v3 — official USFS trail data import.
--
-- Enables PostGIS (available on this Supabase project but not previously
-- used — v1's boundary was a hand-rolled jsonb coordinate array precisely
-- because nothing in this schema used real spatial types yet). Real trail
-- LINE geometry and "intersects the boundary" filtering are exactly what
-- PostGIS is for.
--
-- Two new, isolated tables (never touching `locations`/Marion content):
--   forest_trail_segments — one row per raw USFS GIS record, lossless.
--   forest_trails         — grouped, user-facing trail (spec §9): one row
--                           per distinct trail_no among in-forest segments.
-- Plus one new column on the EXISTING forest_boundaries (a spatially-
-- queryable form of the SAME v1 boundary, not a second boundary), and one
-- new nullable column on the EXISTING forest_locations (a not-yet-used
-- link for future trailhead/story-point locations — spec §10).
--
-- Idempotent: safe to re-run.

create extension if not exists postgis;

-- The same v1 boundary, also expressed as real geometry so trail
-- filtering can use ST_Intersects.
alter table public.forest_boundaries
  add column if not exists geom geometry(MultiPolygon, 4326);

-- ST_MakeValid + ST_CollectionExtract(...,3) + ST_Multi: the raw GeoJSON
-- rings (valid enough for the hand-rolled ray-casting point-in-polygon
-- check used elsewhere) aren't quite valid by PostGIS's stricter topology
-- rules; MakeValid can return a GeometryCollection when it introduces
-- lower-dimension repair artifacts, so this extracts just the polygonal
-- parts back into a clean MultiPolygon.
update public.forest_boundaries
set geom = ST_Multi(ST_CollectionExtract(
  ST_MakeValid(ST_SetSRID(
    ST_GeomFromGeoJSON(jsonb_build_object('type', 'MultiPolygon', 'coordinates', polygon)::text),
    4326
  )),
  3
));

create table if not exists public.forest_trail_segments (
  id                          uuid primary key default gen_random_uuid(),
  forest_id                   uuid references public.forest_boundaries(id) on delete cascade,
  source                      text not null default 'U.S. Forest Service',
  source_dataset              text not null default 'National Forest System Trails (EDW_TrailNFSPublish_01)',
  source_url                  text,
  -- USFS globalid (or objectid fallback) -- the source's actual per-record
  -- unique id. NOT trail_cn: that field is a "trail common number" shared
  -- by every geometry segment of the same logical trail, not unique per
  -- record (confirmed empirically importing Ocala's data).
  source_record_id            text not null unique,
  trail_name                  text,
  trail_no                    text,
  trail_type                  text,
  trail_class                 text,
  trail_surface               text,
  accessibility_status        text,
  national_trail_designation  integer,
  managing_org                text,
  admin_org                   text,
  gis_miles                   numeric,
  source_attributes           jsonb not null default '{}'::jsonb, -- full raw USFS attribute set
  -- MultiLineString (not LineString): the USFS source itself returns some
  -- records as multi-part polylines. Storing every segment as ST_Multi(...)
  -- keeps a true 1:1 row-per-source-record mapping instead of splitting one
  -- official record into synthetic sub-records.
  geom                        geometry(MultiLineString, 4326) not null,
  in_ocala_forest             boolean not null default false, -- real ST_Intersects result
  source_content_hash         text,
  imported_at                 timestamptz not null default now(),
  updated_at                  timestamptz not null default now()
);

create index if not exists forest_trail_segments_forest_idx
  on public.forest_trail_segments (forest_id);
create index if not exists forest_trail_segments_trail_no_idx
  on public.forest_trail_segments (trail_no);
create index if not exists forest_trail_segments_geom_idx
  on public.forest_trail_segments using gist (geom);

create table if not exists public.forest_trails (
  id                          uuid primary key default gen_random_uuid(),
  forest_id                   uuid references public.forest_boundaries(id) on delete cascade,
  trail_no                    text not null unique,
  trail_name                  text, -- copied verbatim from its segments, never invented
  trail_type                  text,
  trail_class                 text,
  trail_surface               text,
  accessibility_status        text,
  national_trail_designation  integer,
  managing_org                text,
  length_miles                numeric, -- sum of segment gis_miles where present; null if none
  segment_count               integer not null default 0,
  geom                        geometry(MultiLineString, 4326),
  -- The trail geometry's own start coordinate — a geometric fact, NOT an
  -- official trailhead facility record (the source has no trailhead
  -- layer). Always labeled as such in the UI.
  geometric_start_lat         double precision,
  geometric_start_lng         double precision,
  source                      text not null default 'U.S. Forest Service',
  source_dataset              text not null default 'National Forest System Trails (EDW_TrailNFSPublish_01)',
  source_url                  text,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now()
);

create index if not exists forest_trails_forest_idx on public.forest_trails (forest_id);
create index if not exists forest_trails_geom_idx on public.forest_trails using gist (geom);

-- GeoJSON projection so the existing Supabase-Flutter client (PostgREST,
-- no PostGIS-aware driver) can read real geometry as plain text, same as
-- any other column.
create or replace view public.forest_trails_with_geojson as
  select ft.*, ST_AsGeoJSON(ft.geom)::text as geom_geojson
  from public.forest_trails ft;

alter table public.forest_locations
  add column if not exists trail_id uuid references public.forest_trails(id);

alter table public.forest_trail_segments enable row level security;
alter table public.forest_trails enable row level security;

do $$
begin
  execute 'drop policy if exists "forest_trail_segments_read" on public.forest_trail_segments';
  execute 'create policy "forest_trail_segments_read" on public.forest_trail_segments '
          'for select to anon, authenticated using (true)';
  execute 'drop policy if exists "forest_trail_segments_write" on public.forest_trail_segments';
  execute 'create policy "forest_trail_segments_write" on public.forest_trail_segments '
          'for all to anon, authenticated using (true) with check (true)';

  execute 'drop policy if exists "forest_trails_read" on public.forest_trails';
  execute 'create policy "forest_trails_read" on public.forest_trails '
          'for select to anon, authenticated using (true)';
  execute 'drop policy if exists "forest_trails_write" on public.forest_trails';
  execute 'create policy "forest_trails_write" on public.forest_trails '
          'for all to anon, authenticated using (true) with check (true)';
end $$;

-- Padded bounding box of a forest boundary, for the import function's
-- initial ArcGIS query prefilter. The pad is generous on purpose — the
-- REAL geographic filter is the ST_Intersects test in rebuild_forest_trails
-- below; this bbox only needs to be wide enough that no boundary-crossing
-- trail segment is missed before that precise test runs.
create or replace function forest_boundary_bbox(
  p_forest_id uuid,
  p_pad_degrees double precision default 0.05
) returns table(minx double precision, miny double precision, maxx double precision, maxy double precision)
language sql
stable
as $$
  select ST_XMin(geom) - p_pad_degrees, ST_YMin(geom) - p_pad_degrees,
         ST_XMax(geom) + p_pad_degrees, ST_YMax(geom) + p_pad_degrees
  from public.forest_boundaries where id = p_forest_id;
$$;

-- Upsert one raw USFS segment, keyed by its stable source_record_id.
-- Skips the write entirely when the incoming content hash matches what's
-- already stored (the source publishes no last-updated field, so a
-- content hash is the refresh's change-detection substitute).
create or replace function import_forest_trail_segment(
  p_forest_id uuid,
  p_source_record_id text,
  p_trail_name text,
  p_trail_no text,
  p_trail_type text,
  p_trail_class text,
  p_trail_surface text,
  p_accessibility_status text,
  p_national_trail_designation integer,
  p_managing_org text,
  p_admin_org text,
  p_gis_miles numeric,
  p_source_attributes jsonb,
  p_geom_geojson text,
  p_content_hash text
) returns void
language plpgsql
as $$
begin
  insert into public.forest_trail_segments (
    forest_id, source_record_id, trail_name, trail_no, trail_type, trail_class,
    trail_surface, accessibility_status, national_trail_designation,
    managing_org, admin_org, gis_miles, source_attributes, geom,
    source_content_hash,
    source_url
  ) values (
    p_forest_id, p_source_record_id, p_trail_name, p_trail_no, p_trail_type, p_trail_class,
    p_trail_surface, p_accessibility_status, p_national_trail_designation,
    p_managing_org, p_admin_org, p_gis_miles, p_source_attributes,
    ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON(p_geom_geojson), 4326)),
    p_content_hash,
    'https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_TrailNFSPublish_01/MapServer/0'
  )
  on conflict (source_record_id) do update set
    trail_name = excluded.trail_name,
    trail_no = excluded.trail_no,
    trail_type = excluded.trail_type,
    trail_class = excluded.trail_class,
    trail_surface = excluded.trail_surface,
    accessibility_status = excluded.accessibility_status,
    national_trail_designation = excluded.national_trail_designation,
    managing_org = excluded.managing_org,
    admin_org = excluded.admin_org,
    gis_miles = excluded.gis_miles,
    source_attributes = excluded.source_attributes,
    geom = excluded.geom,
    source_content_hash = excluded.source_content_hash,
    updated_at = now()
  where forest_trail_segments.source_content_hash is distinct from excluded.source_content_hash;
end;
$$;

-- Recomputes in_ocala_forest (real ST_Intersects against the existing
-- boundary) and rebuilds the grouped forest_trails from qualifying
-- segments. Only ever writes the official-sourced columns by name (never
-- a wildcard update), so future curated columns on forest_trails are
-- never at risk from a refresh.
create or replace function rebuild_forest_trails(p_forest_id uuid)
returns void
language plpgsql
as $$
begin
  update public.forest_trail_segments s
  set in_ocala_forest = sub.intersects,
      updated_at = now()
  from (
    select s2.id,
           exists (
             select 1 from public.forest_boundaries b
             where b.id = p_forest_id and ST_Intersects(s2.geom, b.geom)
           ) as intersects
    from public.forest_trail_segments s2
    where s2.forest_id = p_forest_id
  ) sub
  where s.id = sub.id and s.in_ocala_forest is distinct from sub.intersects;

  with representative as (
    select distinct on (trail_no)
      trail_no, trail_name, trail_type, trail_class, trail_surface,
      accessibility_status, national_trail_designation, managing_org,
      -- geom is a MultiLineString; StartPoint needs a plain LineString, so
      -- take the first vertex of the first part instead.
      ST_Y(ST_PointN(ST_GeometryN(geom, 1), 1)) as start_lat,
      ST_X(ST_PointN(ST_GeometryN(geom, 1), 1)) as start_lng
    from public.forest_trail_segments
    where forest_id = p_forest_id and in_ocala_forest and trail_no is not null
    order by trail_no, gis_miles desc nulls last, id
  ),
  aggregated as (
    -- ST_Collect(geom) alone can return a GeometryCollection even when
    -- every input is already a MultiLineString (observed on this PostGIS
    -- version for single-row groups); CollectionExtract(...,2) + Multi
    -- is the same fix pattern used for the boundary geometry above.
    select trail_no, sum(gis_miles) as length_miles, count(*) as segment_count,
           ST_Multi(ST_CollectionExtract(ST_Collect(geom), 2)) as geom
    from public.forest_trail_segments
    where forest_id = p_forest_id and in_ocala_forest and trail_no is not null
    group by trail_no
  )
  insert into public.forest_trails (
    forest_id, trail_no, trail_name, trail_type, trail_class, trail_surface,
    accessibility_status, national_trail_designation, managing_org,
    length_miles, segment_count, geom, geometric_start_lat, geometric_start_lng
  )
  select
    p_forest_id, r.trail_no, r.trail_name, r.trail_type, r.trail_class, r.trail_surface,
    r.accessibility_status, r.national_trail_designation, r.managing_org,
    a.length_miles, a.segment_count, a.geom, r.start_lat, r.start_lng
  from representative r
  join aggregated a using (trail_no)
  on conflict (trail_no) do update set
    trail_name = excluded.trail_name,
    trail_type = excluded.trail_type,
    trail_class = excluded.trail_class,
    trail_surface = excluded.trail_surface,
    accessibility_status = excluded.accessibility_status,
    national_trail_designation = excluded.national_trail_designation,
    managing_org = excluded.managing_org,
    length_miles = excluded.length_miles,
    segment_count = excluded.segment_count,
    geom = excluded.geom,
    geometric_start_lat = excluded.geometric_start_lat,
    geometric_start_lng = excluded.geometric_start_lng,
    updated_at = now();
end;
$$;
