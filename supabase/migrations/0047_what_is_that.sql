-- ExplorerOS — "What Is That?" location intelligence expansion
--
-- Two small, additive tables. Our own `locations` table remains the primary
-- source of truth for curated history/content — these only ever SUPPLEMENT
-- it: a cache of Google Places data per location, and generated per-topic
-- spoken scripts/audio (DJ Sunny narration, voiced with the existing
-- ElevenLabs integration). No existing table is touched.
--
-- Idempotent: safe to re-run.

create extension if not exists "pgcrypto";

-- Google Places supplementary data, cached per location so repeated topic
-- requests for the same place don't re-hit the Places API every time.
create table if not exists public.what_is_that_place_data (
  id                    uuid primary key default gen_random_uuid(),
  location_id           text not null unique,   -- locations.id
  google_place_id       text,
  formatted_address     text,
  current_name          text,                   -- Google's own name -- "what's here now"
  place_types           text[] not null default '{}',
  business_status       text,                   -- OPERATIONAL / CLOSED_TEMPORARILY / CLOSED_PERMANENTLY
  wheelchair_accessible boolean,
  opening_hours         text,                   -- human-readable weekday text
  photo_url             text,                   -- our own copy (downloaded, not a live Google URL)
  fetched_at            timestamptz not null default now()
);

create index if not exists what_is_that_place_data_location_idx
  on public.what_is_that_place_data (location_id);

-- Generated, topic-scoped spoken scripts + DJ Sunny audio. One row per
-- (location, topic) -- e.g. (silver-springs, history), (silver-springs,
-- whats_here_now). Never invents facts; script is built server-side from
-- verified `locations` + `what_is_that_place_data` fields only.
create table if not exists public.what_is_that_narrations (
  id            uuid primary key default gen_random_uuid(),
  location_id   text not null,
  topic         text not null,
  script        text,
  audio_url     text,
  voice_id      text,
  generated_at  timestamptz,
  created_at    timestamptz not null default now(),
  unique (location_id, topic)
);

create index if not exists what_is_that_narrations_location_idx
  on public.what_is_that_narrations (location_id);

-- RLS: public read; admin (anon/authenticated) write — mirrors location_content.
alter table public.what_is_that_place_data enable row level security;
alter table public.what_is_that_narrations enable row level security;

do $$
begin
  execute 'drop policy if exists "wit_place_data_read" on public.what_is_that_place_data';
  execute 'create policy "wit_place_data_read" on public.what_is_that_place_data '
          'for select to anon, authenticated using (true)';
  execute 'drop policy if exists "wit_place_data_write" on public.what_is_that_place_data';
  execute 'create policy "wit_place_data_write" on public.what_is_that_place_data '
          'for insert to anon, authenticated with check (true)';
  execute 'drop policy if exists "wit_place_data_update" on public.what_is_that_place_data';
  execute 'create policy "wit_place_data_update" on public.what_is_that_place_data '
          'for update to anon, authenticated using (true) with check (true)';

  execute 'drop policy if exists "wit_narrations_read" on public.what_is_that_narrations';
  execute 'create policy "wit_narrations_read" on public.what_is_that_narrations '
          'for select to anon, authenticated using (true)';
  execute 'drop policy if exists "wit_narrations_write" on public.what_is_that_narrations';
  execute 'create policy "wit_narrations_write" on public.what_is_that_narrations '
          'for insert to anon, authenticated with check (true)';
  execute 'drop policy if exists "wit_narrations_update" on public.what_is_that_narrations';
  execute 'create policy "wit_narrations_update" on public.what_is_that_narrations '
          'for update to anon, authenticated using (true) with check (true)';
end $$;
