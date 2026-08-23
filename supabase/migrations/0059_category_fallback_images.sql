-- Real photographs for Discover's category tiers (spec: "should use real
-- photographs where available rather than relying entirely on emoji").
-- Deliberately NOT added to `categories` (migration 0039) -- that table only
-- covers the location-type taxonomy, while Discover's category visuals
-- (shared/design/category_visuals.dart) span locations AND events AND gems
-- through a single keyword-matched bucket system (e.g. "Nightlife",
-- "Festivals", "Food" aren't location types at all). category_key matches
-- that file's canonical bucket keys, not `categories.slug`.
create table if not exists public.category_fallback_images (
  category_key text primary key,
  image_url text not null,
  updated_at timestamptz not null default now()
);

alter table public.category_fallback_images enable row level security;
do $$
begin
  execute 'drop policy if exists "category_fallback_images_read" on public.category_fallback_images';
  execute 'create policy "category_fallback_images_read" on public.category_fallback_images for select to anon, authenticated using (true)';
  execute 'drop policy if exists "category_fallback_images_write" on public.category_fallback_images';
  execute 'create policy "category_fallback_images_write" on public.category_fallback_images for all to authenticated using (true) with check (true)';
end $$;
