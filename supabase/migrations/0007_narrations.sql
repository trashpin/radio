-- Pre-generated narration scripts + audio for any content record.
-- Run in the Supabase SQL editor for project qqeyvhcgirmfokoftiuz.
--
-- Audio is generated once (ElevenLabs) during authoring and stored in Storage,
-- organized by park + category, e.g.:
--   /parks/ocala/wildlife/florida_black_bear-standard_ranger.mp3
-- The app only ever streams `audio_url` for instant playback (online/offline);
-- AI is never called during a user session.

create table if not exists public.narrations (
  id uuid primary key default gen_random_uuid(),
  content_id text not null,          -- id of the narrated record (e.g. species_id)
  content_type text not null,        -- 'species' | 'park' | 'trail' | 'poi' | ...
  park_id text,
  title text,
  narration_type text not null default 'standard_ranger',
  voice_name text,
  voice_id text,
  script text,
  audio_url text,
  duration integer,                  -- seconds
  language text not null default 'en',
  status text not null default 'draft',   -- draft | pending_review | published
  approved boolean not null default false,
  featured boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists narrations_content_idx
  on public.narrations (content_id);
create index if not exists narrations_park_type_idx
  on public.narrations (park_id, content_type);
create unique index if not exists narrations_unique_variant
  on public.narrations (content_id, narration_type, language);

-- keep updated_at fresh
create or replace function public.set_narration_updated_at()
returns trigger as $$
begin new.updated_at = now(); return new; end;
$$ language plpgsql;
drop trigger if exists narrations_touch on public.narrations;
create trigger narrations_touch before update on public.narrations
  for each row execute function public.set_narration_updated_at();

alter table public.narrations enable row level security;

-- App reads approved/published narrations; anon+authenticated may read.
drop policy if exists "read_narrations" on public.narrations;
create policy "read_narrations" on public.narrations
  for select to anon, authenticated using (true);

-- Demo-open write (tighten to admins/service role in production).
drop policy if exists "write_narrations" on public.narrations;
create policy "write_narrations" on public.narrations
  for all to anon, authenticated using (true) with check (true);
