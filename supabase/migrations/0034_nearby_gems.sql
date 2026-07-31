-- ExplorerOS — Nearby Gems
--
-- Admin-curated "Nearby Gems": the ONLY source of Nearby Gems shown to users.
-- Nothing is auto-imported from Google Places or any third party — an admin
-- adds/approves every gem here. The traveler screen shows only ACTIVE gems
-- within the configured distance, sorted nearest-first.
--
-- Idempotent: safe to re-run.

create extension if not exists "pgcrypto";

create table if not exists public.nearby_gems (
  id                uuid primary key default gen_random_uuid(),
  name              text not null,
  category          text,                       -- Restaurant, Coffee, Attraction, …
  badge             text,                        -- Local Favorite | ExplorerOS Pick | Worth the Drive | Hidden Gem
  featured_image    text,
  gallery_images    text[] not null default '{}',
  latitude          double precision,
  longitude         double precision,
  address           text,
  website           text,
  phone             text,
  narration_url     text,                        -- AI narration audio ("Hear Story")
  short_description text,
  long_story        text,
  active            boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index if not exists nearby_gems_active_idx on public.nearby_gems (active);
create index if not exists nearby_gems_geo_idx
  on public.nearby_gems (latitude, longitude);

-- keep updated_at fresh
create or replace function public.nearby_gems_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists nearby_gems_set_updated_at on public.nearby_gems;
create trigger nearby_gems_set_updated_at
  before update on public.nearby_gems
  for each row execute function public.nearby_gems_touch_updated_at();

-- Row-level security: public read; admin (anon/authenticated) write — mirrors
-- the other admin-managed tables in this project. Tighten to authenticated-only
-- in production if desired.
alter table public.nearby_gems enable row level security;

drop policy if exists "nearby_gems_read" on public.nearby_gems;
create policy "nearby_gems_read" on public.nearby_gems
  for select to anon, authenticated using (true);

drop policy if exists "nearby_gems_insert" on public.nearby_gems;
create policy "nearby_gems_insert" on public.nearby_gems
  for insert to anon, authenticated with check (true);

drop policy if exists "nearby_gems_update" on public.nearby_gems;
create policy "nearby_gems_update" on public.nearby_gems
  for update to anon, authenticated using (true) with check (true);

drop policy if exists "nearby_gems_delete" on public.nearby_gems;
create policy "nearby_gems_delete" on public.nearby_gems
  for delete to anon, authenticated using (true);
