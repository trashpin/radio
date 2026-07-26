-- Radio Automation: a professional-style segment library + scheduling rules.
-- radio_segments  = every playable non-music asset (DJ banter, station IDs,
--                   intros/outros, promos, weather/safety, GPS/wildlife intros).
-- radio_schedule_rules = when segments should play (trigger types + priority).
-- Run in the Supabase SQL editor for project qqeyvhcgirmfokoftiuz. Idempotent.

create table if not exists public.radio_segments (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category text not null default 'DJ_BANTER',  -- DJ_BANTER/SONG_INTRO/SONG_OUTRO/STATION_ID/PROMO/WEATHER/SAFETY/GPS_TRANSITION/WILDLIFE_INTRO
  station text not null default 'all',          -- all/country/rock/topHits/kids
  park_id text,                                 -- null = all parks
  voice text,                                   -- voice name/label
  voice_id text,                                -- ElevenLabs voice id
  song_id uuid,                                 -- for SONG_INTRO/OUTRO tied to a song
  script text,
  audio_url text,
  duration integer,                             -- seconds
  generated_by_ai boolean not null default true,
  published boolean not null default false,
  play_count integer not null default 0,
  last_played timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists radio_segments_lookup_idx
  on public.radio_segments (category, station, published);

create table if not exists public.radio_schedule_rules (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  station text not null default 'all',
  park_id text,
  category text,                 -- which segment category this rule plays
  trigger_type text not null,    -- BEFORE_SONG/AFTER_SONG/EVERY_X_SONGS/EVERY_X_MINUTES/TOP_OF_HOUR/...
  trigger_value integer,         -- N for every-X rules
  daypart text,                  -- any/day/night
  priority integer not null default 5,
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);

-- RLS: public read + open writes (matches the rest of the admin content tables).
do $$
declare t text;
begin
  foreach t in array array['radio_segments','radio_schedule_rules'] loop
    execute format('alter table public.%I enable row level security;', t);
    execute format('drop policy if exists "read_%s" on public.%I;', t, t);
    execute format('create policy "read_%s" on public.%I for select to anon, authenticated using (true);', t, t);
    execute format('drop policy if exists "write_%s" on public.%I;', t, t);
    execute format('create policy "write_%s" on public.%I for insert to anon, authenticated with check (true);', t, t);
    execute format('drop policy if exists "update_%s" on public.%I;', t, t);
    execute format('create policy "update_%s" on public.%I for update to anon, authenticated using (true) with check (true);', t, t);
    execute format('drop policy if exists "delete_%s" on public.%I;', t, t);
    execute format('create policy "delete_%s" on public.%I for delete to anon, authenticated using (true);', t, t);
  end loop;
end $$;

-- Segment audio lives in the existing public `voiceovers` bucket.
