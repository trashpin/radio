-- Explorer Sightings ("I See Something") — citizen-science observations.
-- Run in the Supabase SQL editor (or via the CLI) for project qqeyvhcgirmfokoftiuz.
-- Does not duplicate existing tables; references the existing `destinations`.

-- Category reference (future-ready; the app also has a local enum).
create table if not exists public.sighting_categories (
  token text primary key,
  label text not null,
  sort_order integer default 0
);

insert into public.sighting_categories (token, label, sort_order) values
  ('animal','Animal',1),('bird','Bird',2),('plant','Plant',3),('tree','Tree',4),
  ('wildflower','Wildflower',5),('reptile','Reptile',6),('fish','Fish',7),
  ('insect','Insect',8),('scenic_view','Scenic View',9),('waterfall','Waterfall',10),
  ('spring','Spring',11),('historic_site','Historic Site',12),
  ('trail_feature','Trail Feature',13),('other','Other',14)
on conflict (token) do nothing;

-- Main observations table.
create table if not exists public.explorer_sightings (
  sighting_id uuid primary key default gen_random_uuid(),
  user_id text,
  category text not null,
  species text,
  notes text,
  latitude numeric,
  longitude numeric,
  elevation_ft integer,
  destination_id uuid references public.destinations(destination_id) on delete set null,
  park_name text,
  trail text,
  travel_direction text,
  weather text,
  photo_url text,                       -- placeholder for future photo upload
  created_at timestamptz not null default now()
);

create index if not exists explorer_sightings_destination_idx
  on public.explorer_sightings (destination_id);
create index if not exists explorer_sightings_category_idx
  on public.explorer_sightings (category);
create index if not exists explorer_sightings_created_idx
  on public.explorer_sightings (created_at desc);

-- RLS: demo-open (anon can read/insert/delete). TIGHTEN LATER:
--   - insert: to authenticated with check (auth.uid() = user_id::uuid)
--   - delete: restrict to admins/owners
alter table public.explorer_sightings enable row level security;
alter table public.sighting_categories enable row level security;

drop policy if exists "read_categories" on public.sighting_categories;
create policy "read_categories" on public.sighting_categories
  for select to anon, authenticated using (true);

drop policy if exists "read_sightings" on public.explorer_sightings;
create policy "read_sightings" on public.explorer_sightings
  for select to anon, authenticated using (true);

drop policy if exists "insert_sightings" on public.explorer_sightings;
create policy "insert_sightings" on public.explorer_sightings
  for insert to anon, authenticated with check (true);

drop policy if exists "delete_sightings" on public.explorer_sightings;
create policy "delete_sightings" on public.explorer_sightings
  for delete to anon, authenticated using (true);

-- FUTURE (not created yet): sighting_photos, species reference/identification.
