-- ExplorerOS — "Discover This Area", Phase 1: data model + detection.
--
-- Design decision: an "Area" (Historic Downtown Ocala, Silver Springs Area,
-- Ocala National Forest) is NOT a new table — it's a `locations` row with
-- category = 'area', exactly like every other location type. This reuses
-- everything Master Locations already has (name, images, short/long
-- description, narration_script, audio_files, trigger_radius, GPS) instead of
-- building a parallel content system. `trigger_radius` becomes the area's
-- detection radius; `short_description` becomes its intro; `images[0]` is its
-- hero image.
--
-- The 'area' category itself doesn't need a schema change either — Category
-- Manager (already built) lets an admin add unlimited custom categories with
-- zero code changes. This migration just seeds it so it's there by default,
-- the same way migration 0039 seeded the built-in taxonomy.
--
-- Additive only. Idempotent: safe to re-run.

-- The one genuinely new piece of data an Area needs that no other location
-- type has: how long its narrated content takes to listen to, shown on the
-- Discover Screen ("Estimated Listening Time"). Nullable — the UI computes a
-- fallback from content length when it's not set.
alter table public.locations
  add column if not exists estimated_listening_minutes integer;

insert into public.categories (slug, label, sort_order)
values ('area', 'Area / District', 28)
on conflict (lower(slug)) do nothing;
