-- Master SPECIES table — all natural-history content for ExplorerOS.
-- Run in the Supabase SQL editor for project qqeyvhcgirmfokoftiuz.
-- Reuses existing tables: links to `destinations` (park presence) and `media`
-- (assets). Species are NOT stored in `media`; `media` links to species via a
-- new `species_id` FK, and `species.hero_image` may hold a direct URL.

create table if not exists public.species (
  species_id uuid primary key default gen_random_uuid(),
  -- Category taxonomy (matches the discovery grid tokens):
  -- plants, trees, birds, mammals, reptiles, amphibians, fish, insects,
  -- mushrooms, wildflowers, animal_tracks, historic_sites, scenic_views,
  -- waterfalls, springs, trail_features
  category text not null,
  common_name text not null,
  scientific_name text,
  pronunciation text,
  description text,
  -- Identification
  size text,
  weight text,
  color text,
  shape text,
  special_markings text,
  male_vs_female text,
  juvenile_notes text,
  -- Facts
  diet text,
  behavior text,
  life_span text,
  breeding text,
  conservation_status text,
  safety_info text,
  fun_facts text,
  -- Media / linkage
  hero_image text,                              -- optional direct URL (asset lives in storage)
  hero_media_id uuid references public.media(media_id) on delete set null,
  destination_id uuid references public.destinations(destination_id) on delete set null,
  -- Flags
  featured boolean not null default false,
  published boolean not null default true,
  sort_order integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Reserve media for assets: let a media row belong to a species.
alter table public.media
  add column if not exists species_id uuid references public.species(species_id) on delete set null;

create index if not exists species_category_idx on public.species (category);
create index if not exists species_destination_idx on public.species (destination_id);
create index if not exists species_published_idx on public.species (published);
create index if not exists media_species_idx on public.media (species_id);

-- RLS: public read of published; demo-open writes for the Base44 importer.
-- TIGHTEN later: writes → authenticated/admin only.
alter table public.species enable row level security;

drop policy if exists "public_read_species" on public.species;
create policy "public_read_species" on public.species
  for select to anon, authenticated using (published = true);

drop policy if exists "insert_species" on public.species;
create policy "insert_species" on public.species
  for insert to anon, authenticated with check (true);

drop policy if exists "update_species" on public.species;
create policy "update_species" on public.species
  for update to anon, authenticated using (true);

drop policy if exists "delete_species" on public.species;
create policy "delete_species" on public.species
  for delete to anon, authenticated using (true);
