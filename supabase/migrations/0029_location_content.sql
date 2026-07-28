-- ExplorerOS — Location Intelligence: geocoded content index
--
-- The Location Intelligence Engine ranks what to air by DISTANCE, so every
-- content item needs coordinates + place metadata + scheduling fields. This
-- table is the canonical, geocoded content index the engine reads (existing
-- catalogs can be projected into it over time).
--
-- Idempotent: safe to re-run.

create extension if not exists "pgcrypto";

create table if not exists public.location_content (
  id                 uuid primary key default gen_random_uuid(),

  title              text not null default '',
  category           text not null,          -- wildlife, county_history, water, …
  subcategory        text,

  -- Where it is.
  latitude           double precision,
  longitude          double precision,
  county             text,
  city               text,
  state              text,
  park               text,

  -- Scheduling.
  radius             double precision,        -- relevance radius, meters
  priority           integer not null default 0, -- author base bump (0-100)
  estimated_duration integer,                  -- seconds
  cooldown           integer not null default 21600, -- seconds (6h default)
  play_count         integer not null default 0,
  last_played        timestamptz,

  -- Playback.
  audio_url          text,
  text               text,
  destination_code   text,

  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index if not exists location_content_geo_idx
  on public.location_content (latitude, longitude);
create index if not exists location_content_category_idx
  on public.location_content (category);
create index if not exists location_content_county_idx
  on public.location_content (county);
create index if not exists location_content_city_idx on public.location_content (city);
create index if not exists location_content_park_idx on public.location_content (park);

create or replace function public.location_content_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists location_content_set_updated_at on public.location_content;
create trigger location_content_set_updated_at
  before update on public.location_content
  for each row execute function public.location_content_touch_updated_at();

-- Records a play: bumps play_count and stamps last_played (drives cooldown).
create or replace function public.location_content_record_play(p_id uuid)
returns void language plpgsql as $$
begin
  update public.location_content
     set play_count  = coalesce(play_count, 0) + 1,
         last_played = now()
   where id = p_id;
end $$;

-- RLS: public read; admin (anon/authenticated) write — mirrors other tables.
alter table public.location_content enable row level security;

do $$
begin
  execute 'drop policy if exists "location_content_read" on public.location_content';
  execute 'create policy "location_content_read" on public.location_content '
          'for select to anon, authenticated using (true)';
  execute 'drop policy if exists "location_content_write" on public.location_content';
  execute 'create policy "location_content_write" on public.location_content '
          'for insert to anon, authenticated with check (true)';
  execute 'drop policy if exists "location_content_update" on public.location_content';
  execute 'create policy "location_content_update" on public.location_content '
          'for update to anon, authenticated using (true) with check (true)';
  execute 'drop policy if exists "location_content_delete" on public.location_content';
  execute 'create policy "location_content_delete" on public.location_content '
          'for delete to anon, authenticated using (true)';
end $$;
