-- Map Editor support: ensure map_locations exists, add a per-POI trigger radius,
-- and allow update/delete so admins can drag/edit/delete markers.
-- Run in the Supabase SQL editor for project qqeyvhcgirmfokoftiuz.
-- (Self-contained: safe to run even if 0005_map_locations.sql was never applied.)

create table if not exists public.map_locations (
  id uuid primary key default gen_random_uuid(),
  park_code text,
  destination_id uuid,
  category text not null,
  subcategory text,
  name text not null,
  description text,
  latitude double precision not null,
  longitude double precision not null,
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
create index if not exists map_locations_park_idx on public.map_locations (park_code);
create index if not exists map_locations_dest_idx on public.map_locations (destination_id);

alter table public.map_locations enable row level security;
drop policy if exists "public_read_map_locations" on public.map_locations;
create policy "public_read_map_locations" on public.map_locations
  for select to anon, authenticated using (true);
drop policy if exists "insert_map_locations" on public.map_locations;
create policy "insert_map_locations" on public.map_locations
  for insert to anon, authenticated with check (true);
-- New for the editor: allow drag-to-move (update) and delete.
drop policy if exists "update_map_locations" on public.map_locations;
create policy "update_map_locations" on public.map_locations
  for update to anon, authenticated using (true) with check (true);
drop policy if exists "delete_map_locations" on public.map_locations;
create policy "delete_map_locations" on public.map_locations
  for delete to anon, authenticated using (true);
