-- Content tables for the CSV Importer (Points of Interest, Trails, Campgrounds,
-- Historical Events). Self-contained + idempotent — safe to run multiple times
-- and even if earlier migrations were never applied.
-- Run in the Supabase SQL editor for project qqeyvhcgirmfokoftiuz.
--
-- RLS mirrors the existing public.map_locations policy set (public read; insert/
-- update/delete for anon + authenticated) so the admin importer works the same
-- way the map editor already does. Tighten to `authenticated` only later if you
-- want to require sign-in for writes.

-- ── Points of Interest (also used by the Map Editor) ─────────────────────────
create table if not exists public.map_locations (
  id uuid primary key default gen_random_uuid(),
  park_code text,
  destination_id uuid,
  category text,
  subcategory text,
  name text not null,
  description text,
  latitude double precision,
  longitude double precision,
  image_url text,
  gallery_urls text[],
  audio_url text,
  icon text,
  trigger_radius_m integer,
  visibility text default 'public',
  featured boolean default false,
  ai_context text,
  keywords text[],
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.map_locations add column if not exists trigger_radius_m integer;

-- ── Trails ───────────────────────────────────────────────────────────────────
create table if not exists public.trails (
  id uuid primary key default gen_random_uuid(),
  destination_id uuid,
  park_code text,
  name text not null,
  difficulty text,
  distance_miles double precision,
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ── Campgrounds ──────────────────────────────────────────────────────────────
create table if not exists public.campgrounds (
  id uuid primary key default gen_random_uuid(),
  destination_id uuid,
  park_code text,
  name text not null,
  sites integer,
  latitude double precision,
  longitude double precision,
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ── Historical Events ────────────────────────────────────────────────────────
create table if not exists public.historical_events (
  id uuid primary key default gen_random_uuid(),
  destination_id uuid,
  title text not null,
  year integer,
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ── Row-Level Security (public read + open writes, matching map_locations) ────
-- map_locations
alter table public.map_locations enable row level security;
drop policy if exists "public_read_map_locations" on public.map_locations;
create policy "public_read_map_locations" on public.map_locations
  for select to anon, authenticated using (true);
drop policy if exists "insert_map_locations" on public.map_locations;
create policy "insert_map_locations" on public.map_locations
  for insert to anon, authenticated with check (true);
drop policy if exists "update_map_locations" on public.map_locations;
create policy "update_map_locations" on public.map_locations
  for update to anon, authenticated using (true) with check (true);
drop policy if exists "delete_map_locations" on public.map_locations;
create policy "delete_map_locations" on public.map_locations
  for delete to anon, authenticated using (true);

-- trails
alter table public.trails enable row level security;
drop policy if exists "public_read_trails" on public.trails;
create policy "public_read_trails" on public.trails
  for select to anon, authenticated using (true);
drop policy if exists "write_trails" on public.trails;
create policy "write_trails" on public.trails
  for insert to anon, authenticated with check (true);
drop policy if exists "update_trails" on public.trails;
create policy "update_trails" on public.trails
  for update to anon, authenticated using (true) with check (true);
drop policy if exists "delete_trails" on public.trails;
create policy "delete_trails" on public.trails
  for delete to anon, authenticated using (true);

-- campgrounds
alter table public.campgrounds enable row level security;
drop policy if exists "public_read_campgrounds" on public.campgrounds;
create policy "public_read_campgrounds" on public.campgrounds
  for select to anon, authenticated using (true);
drop policy if exists "write_campgrounds" on public.campgrounds;
create policy "write_campgrounds" on public.campgrounds
  for insert to anon, authenticated with check (true);
drop policy if exists "update_campgrounds" on public.campgrounds;
create policy "update_campgrounds" on public.campgrounds
  for update to anon, authenticated using (true) with check (true);
drop policy if exists "delete_campgrounds" on public.campgrounds;
create policy "delete_campgrounds" on public.campgrounds
  for delete to anon, authenticated using (true);

-- historical_events
alter table public.historical_events enable row level security;
drop policy if exists "public_read_historical_events" on public.historical_events;
create policy "public_read_historical_events" on public.historical_events
  for select to anon, authenticated using (true);
drop policy if exists "write_historical_events" on public.historical_events;
create policy "write_historical_events" on public.historical_events
  for insert to anon, authenticated with check (true);
drop policy if exists "update_historical_events" on public.historical_events;
create policy "update_historical_events" on public.historical_events
  for update to anon, authenticated using (true) with check (true);
drop policy if exists "delete_historical_events" on public.historical_events;
create policy "delete_historical_events" on public.historical_events
  for delete to anon, authenticated using (true);
