-- Geolocated points for the real-time "Around Me" map discovery system.
-- Every marker on the map comes from this table (nothing hardcoded).
-- Run in the Supabase SQL editor for project qqeyvhcgirmfokoftiuz.

create table if not exists public.map_locations (
  id uuid primary key default gen_random_uuid(),
  park_code text,
  category text not null,          -- mammals, birds, plants, trees, springs, trails, campgrounds, historic_sites, scenic_overlooks, ...
  subcategory text,
  name text not null,
  description text,
  latitude numeric not null,
  longitude numeric not null,
  image_url text,
  gallery_urls text[],
  audio_url text,
  icon text,
  visibility text default 'public',
  featured boolean not null default false,
  ai_context text,
  keywords text[],
  destination_id uuid references public.destinations(destination_id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists map_locations_geo_idx on public.map_locations (latitude, longitude);
create index if not exists map_locations_category_idx on public.map_locations (category);
create index if not exists map_locations_park_idx on public.map_locations (park_code);

-- PERFORMANCE (future): enable PostGIS and add a geography column + GIST index
-- so nearby queries use ST_DWithin(geom, point, radius_m) instead of scanning:
--   create extension if not exists postgis;
--   alter table public.map_locations add column geom geography(Point,4326)
--     generated always as (st_point(longitude, latitude)::geography) stored;
--   create index map_locations_gix on public.map_locations using gist (geom);

alter table public.map_locations enable row level security;
drop policy if exists "public_read_map_locations" on public.map_locations;
create policy "public_read_map_locations" on public.map_locations
  for select to anon, authenticated using (true);
drop policy if exists "insert_map_locations" on public.map_locations;
create policy "insert_map_locations" on public.map_locations
  for insert to anon, authenticated with check (true);
