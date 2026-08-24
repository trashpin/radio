-- Marion County Adventures — reusable STORY PRODUCTION SYSTEM.
--
-- Adds ONE new authoring/production table, `mission_story_steps`, that lets
-- an admin build an entire adventure as an ordered sequence of steps
-- (introduction/travel/approach/arrival/discovery/QR/old world/clue/final
-- reveal), each with its own character, script, presentation type
-- (audio/avatar/text+audio), trigger, and production status.
--
-- This is deliberately NOT a second runtime/GPS system. The live GPS
-- trigger evaluation the player actually experiences
-- (MissionStoryEngine/ActiveMissionController) keeps reading exactly the
-- tables it already reads (mission_travel_stories, mission_stops,
-- old_worlds, missions) -- nothing about that pipeline changes here. A
-- story step's content is authored and produced (script -> voice ->
-- optional avatar -> preview) in this table, then PUBLISHED into the
-- matching existing runtime row -- the Story Builder is the authoring
-- surface; the existing tables remain the single source of truth the game
-- actually plays from. See mission_story_step.dart's own doc comment for
-- the step_type -> runtime table mapping.

alter table public.mission_characters
  add column if not exists heygen_avatar_id text;

create table if not exists public.mission_story_steps (
  id uuid primary key default gen_random_uuid(),
  mission_id uuid not null references public.missions(id) on delete cascade,
  -- Null for mission-level steps (introduction, final reveal) that aren't
  -- tied to one physical stop.
  stop_id uuid references public.mission_stops(id) on delete cascade,
  step_order integer not null default 0,
  title text not null,
  -- Free text (not a fixed enum, matching this schema's existing
  -- category/difficulty/trigger_type philosophy): mission_introduction,
  -- travel_story, approach_story, arrival, discovery, qr, old_world, clue,
  -- final_reveal.
  step_type text not null default 'travel_story',
  character_id uuid references public.mission_characters(id) on delete set null,
  script text,
  -- audio_only | avatar_video | text_audio
  presentation_type text not null default 'audio_only',
  audio_url text,
  avatar_video_url text,
  -- MISSION_START | DISTANCE_FROM_DESTINATION | APPROACH | ARRIVAL |
  -- QR_SCAN | MANUAL_DISCOVERY | PREVIOUS_STEP_COMPLETE | MISSION_COMPLETE
  -- (stored lowercase, matching this schema's free-text convention).
  trigger_type text not null default 'distance_from_destination',
  trigger_distance_meters double precision,
  qr_portal_id uuid references public.qr_portals(id) on delete set null,
  required_previous_step_id uuid references public.mission_story_steps(id) on delete set null,
  clue_text text,
  question_text text,
  answer_text text,
  xp_reward integer not null default 0,
  next_step_id uuid references public.mission_story_steps(id) on delete set null,
  -- draft | script_approved | audio_generated | video_generated | ready | published
  production_status text not null default 'draft',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists mission_story_steps_mission_idx on public.mission_story_steps(mission_id, step_order);
create index if not exists mission_story_steps_stop_idx on public.mission_story_steps(stop_id);
create index if not exists mission_story_steps_character_idx on public.mission_story_steps(character_id);

alter table public.mission_story_steps enable row level security;
do $$
begin
  execute 'create policy "mission_story_steps_read" on public.mission_story_steps for select to anon, authenticated using (true)';
  execute 'create policy "mission_story_steps_write" on public.mission_story_steps for all to authenticated using (true) with check (true)';
end $$;
