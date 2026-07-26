-- Pre-generated DJ banter clips (a line of banter rendered to audio in a
-- specific DJ's ElevenLabs voice). The app plays these between songs so the
-- on-air voice matches the DJ personality; it falls back to on-device TTS when
-- no clip matches. Populated by tool/dj_audio.dart.
-- Run in the Supabase SQL editor for project qqeyvhcgirmfokoftiuz. Idempotent.

create table if not exists public.dj_banter_clips (
  id uuid primary key default gen_random_uuid(),
  dj_id text,
  voice_id text,
  voice_name text,
  station text not null default 'all',   -- DjStation enum name: all/country/rock/topHits/kids
  situation text not null,               -- BanterSituation enum name: songOutro/stationId/...
  text text,
  audio_url text not null,
  created_at timestamptz not null default now()
);
create index if not exists dj_banter_clips_lookup_idx
  on public.dj_banter_clips (station, situation);

alter table public.dj_banter_clips enable row level security;
drop policy if exists "public_read_dj_banter_clips" on public.dj_banter_clips;
create policy "public_read_dj_banter_clips" on public.dj_banter_clips
  for select to anon, authenticated using (true);
drop policy if exists "write_dj_banter_clips" on public.dj_banter_clips;
create policy "write_dj_banter_clips" on public.dj_banter_clips
  for insert to anon, authenticated with check (true);
drop policy if exists "update_dj_banter_clips" on public.dj_banter_clips;
create policy "update_dj_banter_clips" on public.dj_banter_clips
  for update to anon, authenticated using (true) with check (true);
drop policy if exists "delete_dj_banter_clips" on public.dj_banter_clips;
create policy "delete_dj_banter_clips" on public.dj_banter_clips
  for delete to anon, authenticated using (true);

-- Clips are stored in the existing public `voiceovers` bucket (already has
-- storage policies), under dj/<station>/.
