-- Story Studio: the AI story-production knowledge engine. Stories are generated
-- ahead of time, reviewed/approved, voiced, and played when a visitor enters
-- the story's GPS zone. One table holds the whole lifecycle.
-- Run in the Supabase SQL editor for project qqeyvhcgirmfokoftiuz. Idempotent.

create table if not exists public.story_library (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  park_id text,                                  -- null = all parks
  location text,                                 -- e.g. "Silver Glen Springs"
  category text not null default 'PARK_HISTORY',
  variation text,                                -- Historical/Wildlife/Family/...
  collection text,                               -- grouping name
  gps_zone_id text,
  latitude double precision,
  longitude double precision,
  trigger_radius_m integer default 150,
  transcript text,
  audio_url text,
  voice text,
  voice_id text,
  duration integer,
  audience text default 'general',
  narration_style text default 'ranger',
  status text not null default 'draft',          -- draft/review/approved/generating_audio/completed/failed
  approved boolean not null default false,
  published boolean not null default false,
  play_count integer not null default 0,
  last_played timestamptz,
  created_by text,
  version_number integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists story_library_lookup_idx
  on public.story_library (park_id, category, published);
create index if not exists story_library_geo_idx
  on public.story_library (latitude, longitude);

alter table public.story_library enable row level security;
drop policy if exists "read_story_library" on public.story_library;
create policy "read_story_library" on public.story_library
  for select to anon, authenticated using (true);
drop policy if exists "write_story_library" on public.story_library;
create policy "write_story_library" on public.story_library
  for insert to anon, authenticated with check (true);
drop policy if exists "update_story_library" on public.story_library;
create policy "update_story_library" on public.story_library
  for update to anon, authenticated using (true) with check (true);
drop policy if exists "delete_story_library" on public.story_library;
create policy "delete_story_library" on public.story_library
  for delete to anon, authenticated using (true);

-- Story audio lives in the existing public `narration` bucket, under stories/.
