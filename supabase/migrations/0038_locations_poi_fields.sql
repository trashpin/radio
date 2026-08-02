-- ExplorerOS — richer Point-of-Interest fields on the master `locations` table
--
-- Extends the single, county-agnostic `locations` table with the descriptive,
-- logistical, and accessibility fields a full CMS needs. Nothing here is
-- Marion-specific — every county/state reuses the exact same schema. All fields
-- are optional so existing rows and the app keep working before/after this runs.
--
-- Idempotent: safe to re-run.

alter table public.locations
  add column if not exists state                text,
  add column if not exists short_description    text,
  add column if not exists long_description     text,
  add column if not exists narration_script     text,
  add column if not exists hours                text,
  add column if not exists admission            text,
  add column if not exists external_website     text,
  add column if not exists parking_info         text,
  add column if not exists restrooms            text,
  add column if not exists difficulty           text,
  add column if not exists tags                 text[] not null default '{}',
  add column if not exists family_friendly      boolean,
  add column if not exists pet_friendly         boolean,
  add column if not exists wheelchair_accessible boolean;

-- Helps county/state scoped queries as the dataset grows to many counties.
create index if not exists locations_state_county_idx
  on public.locations (state, county);
create index if not exists locations_category_idx
  on public.locations (category);
