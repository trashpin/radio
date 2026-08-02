-- ExplorerOS — County Content Management System, Phase 2: manageable categories.
--
-- `locations.category` (migration 0031) was already free text, not a foreign
-- key — so this table doesn't require any change to `locations` at all. It
-- adds an admin-editable list of categories that:
--   1) starts seeded with every existing built-in LocationType (Dart enum),
--      so nothing that already reads `category` changes behavior, and
--   2) lets an admin add brand-new categories beyond the built-in list
--      ("Support unlimited categories").
--
-- Idempotent: safe to re-run.

create extension if not exists "pgcrypto";

create table if not exists public.categories (
  id          uuid primary key default gen_random_uuid(),
  slug        text not null,          -- matches `locations.category` values
  label       text not null,          -- display name shown in the Admin Panel
  icon        text,                   -- optional Material icon name, admin-set
  sort_order  integer not null default 0,
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create unique index if not exists categories_slug_uidx
  on public.categories (lower(slug));
create index if not exists categories_active_idx on public.categories (active);
create index if not exists categories_sort_idx on public.categories (sort_order);

create or replace function public.categories_touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

drop trigger if exists categories_set_updated_at on public.categories;
create trigger categories_set_updated_at
  before update on public.categories
  for each row execute function public.categories_touch_updated_at();

-- Seed with every built-in LocationType id (features/locations/models/
-- master_location.dart) so the Admin Panel shows the full existing taxonomy
-- as manageable rows from day one, in the same order they're defined in Dart.
insert into public.categories (slug, label, sort_order) values
  ('county', 'County', 0),
  ('city', 'City', 1),
  ('community', 'Community', 2),
  ('lake', 'Lake', 3),
  ('river', 'River', 4),
  ('spring', 'Spring', 5),
  ('forest', 'Forest', 6),
  ('state_park', 'State Park', 7),
  ('national_park', 'National Park', 8),
  ('county_park', 'County Park', 9),
  ('historic_site', 'Historic Site', 10),
  ('historic_district', 'Historic District', 11),
  ('scenic_road', 'Scenic Road', 12),
  ('trail', 'Trail', 13),
  ('trailhead', 'Trailhead', 14),
  ('campground', 'Campground', 15),
  ('boat_ramp', 'Boat Ramp', 16),
  ('visitor_center', 'Visitor Center', 17),
  ('wildlife_viewing', 'Wildlife Viewing', 18),
  ('scenic_overlook', 'Scenic Overlook', 19),
  ('museum', 'Museum', 20),
  ('attraction', 'Attraction', 21),
  ('restaurant', 'Restaurant', 22),
  ('gas_station', 'Gas Station', 23),
  ('parking', 'Parking', 24),
  ('safety_alert', 'Safety Alert', 25),
  ('hidden_gem', 'Hidden Gem', 26),
  ('point_of_interest', 'Point of Interest', 27)
on conflict (lower(slug)) do nothing;

alter table public.categories enable row level security;
do $$
begin
  execute 'drop policy if exists "categories_read" on public.categories';
  execute 'create policy "categories_read" on public.categories for select to anon, authenticated using (true)';
  execute 'drop policy if exists "categories_write" on public.categories';
  execute 'create policy "categories_write" on public.categories for insert to anon, authenticated with check (true)';
  execute 'drop policy if exists "categories_update" on public.categories';
  execute 'create policy "categories_update" on public.categories for update to anon, authenticated using (true) with check (true)';
  execute 'drop policy if exists "categories_delete" on public.categories';
  execute 'create policy "categories_delete" on public.categories for delete to anon, authenticated using (true)';
end $$;
