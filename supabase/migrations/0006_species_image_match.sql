-- Image Matching support for the master `species` catalog.
-- Run in the Supabase SQL editor for project qqeyvhcgirmfokoftiuz.

-- Match + image columns on species.
alter table public.species add column if not exists match_key text;
alter table public.species add column if not exists image_url text;
alter table public.species add column if not exists thumbnail_url text;
alter table public.species add column if not exists image_verified boolean not null default false;

create index if not exists species_match_key_idx on public.species (match_key);

-- Backfill match_key from common_name using the same rules as the app's
-- normalizer: spaces → underscore, drop punctuation, collapse underscores.
update public.species
set match_key = trim(both '_' from
      regexp_replace(
        regexp_replace(
          regexp_replace(lower(common_name), '\s+', '_', 'g'),
          '[^a-z0-9_]', '', 'g'),
        '_+', '_', 'g'))
where match_key is null;

-- Queue of images with no (single) species match, for manual assignment.
create table if not exists public.unmatched_images (
  id uuid primary key default gen_random_uuid(),
  filename text not null,
  match_key text,
  storage_path text,
  park_code text,
  category text,
  assigned_species_id uuid references public.species(species_id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.unmatched_images enable row level security;
drop policy if exists "rw_unmatched_images" on public.unmatched_images;
create policy "rw_unmatched_images" on public.unmatched_images
  for all to anon, authenticated using (true) with check (true);

-- STORAGE: create a public `species_images` bucket for uploads, organized by
-- park/category (e.g. ocala/plants/saw_palmetto.jpg). Thumbnails use Supabase
-- image transforms: /storage/v1/render/image/public/species_images/<path>?width=240
-- Browser uploads require an INSERT storage policy (or a server-side/service
-- key), since anon uploads are blocked by default.
