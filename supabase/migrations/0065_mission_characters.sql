-- Marion County Adventures — CHARACTER and VOICE system.
--
-- Reuses the existing ElevenLabs integration end to end: characters store an
-- ElevenLabs voice_id exactly like `mission_travel_stories.voice_id`/
-- `old_worlds.voice_id` already do (migration 0063), and audio generation
-- still goes through the SAME `discover-narration` edge function every other
-- mission narration already calls -- nothing new is built server-side. This
-- migration only adds the reusable Character structure and links existing
-- story-scene tables to it; it does not touch existing location or mission
-- content records.
--
-- CHARACTER -> VOICE ID: a scene names a character, and the character's own
-- voice_id is what actually gets used -- never re-selected per scene. The
-- existing free-text speaker_name/voice_id/narrator_name columns on
-- mission_travel_stories/old_worlds are left in place as the fallback for
-- content that doesn't (yet) have a character record, so nothing existing
-- breaks.

create table if not exists public.mission_characters (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  image_url text,
  description text,
  -- Free text, not a fixed enum -- matches this table's own
  -- category/difficulty philosophy elsewhere in this schema. Suggested
  -- vocabulary: narrator, historical_character, fictional_character,
  -- explorer, historian, ranger, local_guide, mystery_character.
  character_type text,
  personality text,
  role text,
  -- The ElevenLabs voice this character always speaks with. Nullable so a
  -- character can be drafted before a voice is assigned -- scenes using it
  -- simply fall back to the shared global default voice until one is set,
  -- same as every other optional voice_id in this schema.
  voice_id text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Story scenes gain an optional character link. All four are nullable and
-- additive -- existing rows (free-text speaker_name/narrator_name/voice_id)
-- keep working exactly as before.
alter table public.missions
  add column if not exists intro_character_id uuid references public.mission_characters(id) on delete set null;

alter table public.mission_stops
  add column if not exists arrival_character_id uuid references public.mission_characters(id) on delete set null;

alter table public.mission_travel_stories
  add column if not exists character_id uuid references public.mission_characters(id) on delete set null;

alter table public.old_worlds
  add column if not exists character_id uuid references public.mission_characters(id) on delete set null;

create index if not exists mission_characters_active_idx on public.mission_characters(active);
create index if not exists missions_intro_character_idx on public.missions(intro_character_id);
create index if not exists mission_stops_arrival_character_idx on public.mission_stops(arrival_character_id);
create index if not exists mission_travel_stories_character_idx on public.mission_travel_stories(character_id);
create index if not exists old_worlds_character_idx on public.old_worlds(character_id);

alter table public.mission_characters enable row level security;
do $$
begin
  execute 'create policy "mission_characters_read" on public.mission_characters for select to anon, authenticated using (true)';
  execute 'create policy "mission_characters_write" on public.mission_characters for all to authenticated using (true) with check (true)';
end $$;
