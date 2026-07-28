-- ExplorerOS — GPS-Aware DJ Banter Studio
--
-- A per-destination banter library so the DJ sounds like a live host traveling
-- with the visitor. Each destination supports dozens of unique clips per
-- category (target 20–50), the Radio Director selects them with cooldown +
-- never-repeat-in-a-trip rules, and every clip can reference live GPS context
-- (park, county, road, nearby lakes/rivers/springs/trails/historic sites,
-- nearby wildlife, upcoming attraction, guide mode).
--
-- `dj_banter`          — the banter library (canonical for this feature).
-- `dj_banter_versions` — edit history per clip (Version History).
--
-- Generation (OpenAI text) + voicing (ElevenLabs audio) run server-side via the
-- tools in tool/. This migration is the schema + control surface. Idempotent.

create extension if not exists "pgcrypto";

create table if not exists public.dj_banter (
  id                 uuid primary key default gen_random_uuid(),

  -- Anchor to a destination (either link is fine; code is the business key).
  destination_id     uuid,
  destination_code   text,

  -- One of the 19 studio categories (welcome, arrival, history_tease, …).
  category           text not null,

  -- The conversational line. May contain {placeholders} filled from live GPS
  -- context at playback time (e.g. {upcoming_attraction}, {county}, {road}).
  text               text not null default '',

  -- Voicing.
  audio_url          text,
  voice_id           text,
  voice_name         text,
  duration           double precision,

  -- GPS targeting: a named region and/or a geofence the clip is relevant to.
  gps_region         text,
  latitude           double precision,
  longitude          double precision,
  radius_m           double precision,

  -- The guide mode this clip fits (null = any).
  guide_mode         text,

  status             text not null default 'draft', -- draft|approved|published|archived
  tags               text[] default '{}',

  -- Rotation bookkeeping (never repeat the same banter during a trip).
  last_played        timestamptz,
  play_count         integer not null default 0,
  trip_played        integer not null default 0,
  destination_played integer not null default 0,

  version            integer not null default 1,

  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index if not exists dj_banter_dest_cat_idx
  on public.dj_banter (destination_code, category);
create index if not exists dj_banter_category_idx on public.dj_banter (category);
create index if not exists dj_banter_status_idx on public.dj_banter (status);
create index if not exists dj_banter_region_idx on public.dj_banter (gps_region);
create index if not exists dj_banter_tags_idx on public.dj_banter using gin (tags);

-- Per-clip edit history (Version History in the studio).
create table if not exists public.dj_banter_versions (
  id          uuid primary key default gen_random_uuid(),
  banter_id   uuid not null references public.dj_banter (id) on delete cascade,
  version     integer not null,
  text        text,
  voice_id    text,
  voice_name  text,
  author      text,
  created_at  timestamptz not null default now()
);

create index if not exists dj_banter_versions_banter_idx
  on public.dj_banter_versions (banter_id, version desc);

create or replace function public.dj_banter_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists dj_banter_set_updated_at on public.dj_banter;
create trigger dj_banter_set_updated_at
  before update on public.dj_banter
  for each row execute function public.dj_banter_touch_updated_at();

-- Records a play: bumps counters, stamps last_played (server-truth for
-- play_count/destination_played; trip_played is per-session and also bumped).
create or replace function public.dj_banter_record_play(p_id uuid)
returns void language plpgsql as $$
begin
  update public.dj_banter
     set play_count         = coalesce(play_count, 0) + 1,
         destination_played = coalesce(destination_played, 0) + 1,
         trip_played        = coalesce(trip_played, 0) + 1,
         last_played        = now()
   where id = p_id;
end $$;

-- Resets per-trip counters (called when a new trip/session begins).
create or replace function public.dj_banter_reset_trip()
returns void language plpgsql as $$
begin
  update public.dj_banter set trip_played = 0 where trip_played <> 0;
end $$;

-- RLS: public read; admin (anon/authenticated) write — mirrors the other admin
-- tables. Tighten to authenticated-only in production.
alter table public.dj_banter enable row level security;
alter table public.dj_banter_versions enable row level security;

do $$
declare t text;
begin
  foreach t in array array['dj_banter', 'dj_banter_versions'] loop
    execute format('drop policy if exists "%1$s_read" on public.%1$s', t);
    execute format('create policy "%1$s_read" on public.%1$s '
                   'for select to anon, authenticated using (true)', t);
    execute format('drop policy if exists "%1$s_write" on public.%1$s', t);
    execute format('create policy "%1$s_write" on public.%1$s '
                   'for insert to anon, authenticated with check (true)', t);
    execute format('drop policy if exists "%1$s_update" on public.%1$s', t);
    execute format('create policy "%1$s_update" on public.%1$s '
                   'for update to anon, authenticated using (true) with check (true)', t);
    execute format('drop policy if exists "%1$s_delete" on public.%1$s', t);
    execute format('create policy "%1$s_delete" on public.%1$s '
                   'for delete to anon, authenticated using (true)', t);
  end loop;
end $$;
