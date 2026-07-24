-- ExplorerOS — music library schema
--
-- Tables for the Music Management feature. Column names match the Dart models'
-- fromJson/toJson exactly. Audio + artwork BYTES live in Supabase Storage
-- (buckets `music_audio`, `music_artwork`); these tables hold metadata + the
-- resulting public URLs.
--
-- RLS: demo-open on all music tables so the read-only app can SELECT and the
-- import tools can INSERT with the anon key. TIGHTEN to authenticated/admin
-- policies before production.

create table if not exists albums (
  id          text primary key,
  title       text not null,
  artist      text,
  year        integer,
  artwork_id  text,
  description text
);

create table if not exists genres (
  id          text primary key,
  name        text not null,
  description text
);

create table if not exists moods (
  id          text primary key,
  name        text not null,
  description text
);

create table if not exists artworks (
  id           text primary key,
  url          text not null,
  width        integer,
  height       integer,
  storage_path text
);

create table if not exists music_metadata (
  id         text primary key,
  song_id    text not null,
  album_id   text,
  genre_id   text,
  mood_id    text,
  artwork_id text,
  bpm        integer,
  year       integer,
  explicit   boolean default false,
  tags       text[] default '{}',
  ai_tagged  boolean default false
);

create table if not exists playlists (
  id          text primary key,
  name        text not null,
  description text,
  song_ids    text[] default '{}'
);

create table if not exists station_assignments (
  id         text primary key,
  song_id    text not null,
  station_id text not null,
  weight     double precision default 1.0
);

create table if not exists gps_music_triggers (
  id            text primary key,
  song_id       text not null,
  latitude      double precision,
  longitude     double precision,
  radius_meters double precision default 300,
  park_id       text,
  state         text,
  one_shot      boolean default true
);

create table if not exists upload_jobs (
  id              text primary key,
  type            text,
  status          text default 'queued',
  total_items     integer default 0,
  processed_items integer default 0,
  error           text,
  created_at      timestamptz default now()
);

-- RLS (demo-open — tighten before production) --------------------------------
do $$
declare
  music_table text;
begin
  foreach music_table in array array[
    'albums','genres','moods','artworks','music_metadata','playlists',
    'station_assignments','gps_music_triggers','upload_jobs'
  ] loop
    execute format('alter table %I enable row level security;', music_table);
    execute format(
      'create policy %I on %I for all using (true) with check (true);',
      music_table || '_demo_all', music_table);
  end loop;
end $$;
