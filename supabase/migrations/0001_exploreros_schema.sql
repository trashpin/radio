-- ExplorerOS — database schema
--
-- Creates every table the mobile app reads/writes and matches the exact column
-- names used by the Dart models' fromJson/toJson. IDs are text to align with the
-- app's string ids. Read-only destination CONTENT is world-readable via anon
-- (RLS SELECT policy); USER-OWNED tables are left demo-open with a note to
-- tighten to auth.uid() once authentication is added.
--
-- Apply via the Supabase SQL editor or `supabase db push`.

-- =========================================================================
-- Destination content (read-only for the app)
-- =========================================================================

create table if not exists destinations (
  id             text primary key,
  name           text not null,
  description    text,
  image_url      text,
  location       text,
  category       text,
  featured       boolean default false,
  distance_label text
);

create table if not exists parks (
  id             text primary key,
  destination_id text references destinations(id),
  name           text not null,
  description    text,
  image_url      text,
  location       text
);

create table if not exists stops (
  id          text primary key,
  park_id     text references parks(id),
  name        text not null,
  description text,
  image_url   text,
  latitude    double precision,
  longitude   double precision,
  order_index integer
);

create table if not exists stories (
  id        text primary key,
  park_id   text references parks(id),
  stop_id   text references stops(id),
  title     text not null,
  body      text,
  image_url text
);

create table if not exists wildlife (
  id              text primary key,
  park_id         text references parks(id),
  name            text not null,
  scientific_name text,
  description     text,
  image_url       text
);

create table if not exists plants (
  id              text primary key,
  park_id         text references parks(id),
  name            text not null,
  scientific_name text,
  description     text,
  image_url       text
);

-- =========================================================================
-- Radio content (read-only for the app)
-- =========================================================================

create table if not exists radio_stations (
  id             text primary key,
  name           text not null,
  destination_id text references destinations(id),
  description    text,
  image_url      text,
  stream_url     text
);

create table if not exists station_profiles (
  id              text primary key,
  station_id      text references radio_stations(id),
  name            text not null,
  description     text,
  genre           text,
  mood            text,
  target_audience text,
  tags            text[] default '{}'
);

create table if not exists station_rules (
  id                        text primary key,
  station_id                text references radio_stations(id),
  station_id_every_tracks   integer default 5,
  announcement_every_tracks integer default 4,
  story_every_tracks        integer default 3,
  allow_ambient             boolean default true,
  shuffle_music             boolean default true
);

create table if not exists songs (
  id               text primary key,
  station_id       text references radio_stations(id),
  title            text not null,
  artist           text,
  audio_url        text,
  duration_seconds integer
);

create table if not exists narrations (
  id               text primary key,
  story_id         text references stories(id),
  stop_id          text references stops(id),
  title            text not null,
  audio_url        text,
  duration_seconds integer,
  transcript       text
);

create table if not exists announcements (
  id               text primary key,
  title            text not null,
  kind             text default 'scheduled',
  station_id       text references radio_stations(id),
  audio_url        text,
  duration_seconds integer,
  interval_minutes integer,
  park_id          text,
  state            text,
  tags             text[] default '{}'
);

create table if not exists gps_audio_triggers (
  id               text primary key,
  title            text not null,
  latitude         double precision,
  longitude        double precision,
  radius_meters    double precision default 150,
  narration_id     text,
  audio_url        text,
  duration_seconds integer,
  park_id          text,
  state            text,
  one_shot         boolean default true,
  tags             text[] default '{}'
);

-- =========================================================================
-- GPS geometry (read-only for the app)
-- =========================================================================

create table if not exists park_boundaries (
  id                     text primary key,
  destination_id         text,
  park_id                text references parks(id),
  name                   text not null,
  latitude               double precision,
  longitude              double precision,
  radius_meters          double precision default 1000,
  approach_radius_meters double precision
);

create table if not exists state_boundaries (
  id            text primary key,
  code          text not null,
  name          text not null,
  min_latitude  double precision,
  max_latitude  double precision,
  min_longitude double precision,
  max_longitude double precision
);

create table if not exists county_boundaries (
  id            text primary key,
  name          text not null,
  state_code    text,
  min_latitude  double precision,
  max_latitude  double precision,
  min_longitude double precision,
  max_longitude double precision
);

-- =========================================================================
-- User-owned data (writable; sync)
-- =========================================================================

create table if not exists user_favorites (
  id          text primary key,
  user_id     text not null,
  entity_type text not null,
  entity_id   text not null,
  created_at  timestamptz default now()
);

create table if not exists downloads (
  id          text primary key,
  entity_type text not null,
  entity_id   text not null,
  status      text default 'queued',
  progress    double precision default 0,
  size_bytes  bigint,
  local_path  text
);

create table if not exists location_history (
  id                        text primary key,
  latitude                  double precision,
  longitude                 double precision,
  timestamp                 timestamptz,
  accuracy_meters           double precision,
  heading_degrees           double precision,
  speed_mps                 double precision,
  elevation_meters          double precision,
  movement_state            text,
  travel_mode               text,
  state_code                text,
  park_id                   text,
  destination_id            text,
  distance_travelled_meters double precision default 0
);

create table if not exists travel_sessions (
  id                        text primary key,
  started_at                timestamptz,
  ended_at                  timestamptz,
  active                    boolean default true,
  fix_count                 integer default 0,
  distance_travelled_meters double precision default 0,
  max_speed_mps             double precision default 0,
  parks_visited             integer default 0,
  attractions_visited       integer default 0
);

create table if not exists playback_history (
  id         text primary key,
  segment_id text not null,
  title      text,
  type       text,
  played_at  timestamptz default now(),
  station_id text
);

-- =========================================================================
-- Row Level Security
-- =========================================================================
-- Content: world-readable (anon SELECT). User data: demo-open — REPLACE the
-- "demo write" policies with auth.uid()-scoped policies once auth is wired.

do $$
declare
  content_table text;
  user_table text;
begin
  foreach content_table in array array[
    'destinations','parks','stops','stories','wildlife','plants',
    'radio_stations','station_profiles','station_rules','songs','narrations',
    'announcements','gps_audio_triggers','park_boundaries','state_boundaries',
    'county_boundaries'
  ] loop
    execute format('alter table %I enable row level security;', content_table);
    execute format(
      'create policy %I on %I for select using (true);',
      content_table || '_public_read', content_table);
  end loop;

  foreach user_table in array array[
    'user_favorites','downloads','location_history','travel_sessions',
    'playback_history'
  ] loop
    execute format('alter table %I enable row level security;', user_table);
    -- DEMO ONLY: open read+write. Replace with auth.uid() = user_id policies.
    execute format(
      'create policy %I on %I for all using (true) with check (true);',
      user_table || '_demo_all', user_table);
  end loop;
end $$;
