-- Marion County Adventures — INTERACTIVE GUIDE SYSTEM.
--
-- A per-adventure sequence of beats always delivered by THE GUIDE
-- (distinct from mission_story_steps, which is the adventure CHARACTERS'
-- own story authoring surface -- Amos, Thomas, etc. never speak through
-- this table). Deliberately reuses rather than duplicates:
--   - mission_puzzles for RIDDLE/QUESTION answer-checking + progressive
--     hints (puzzle_id, not a second hint system).
--   - mission_map_pieces for CLUE/MAP/DISCOVERY unlocks (unlocks_map_piece_id,
--     the same column shape already used on mission_travel_stories/old_worlds).
--   - mission_progress.fired_content_ids for "has the player already seen
--     this Guide Step" -- no new per-player tracking table. A guide_steps
--     row's own id is added to that same array the instant it's shown,
--     exactly like a travel story today.

create table if not exists public.guide_steps (
  id uuid primary key default gen_random_uuid(),
  mission_id uuid not null references public.missions(id) on delete cascade,
  -- Null = mission-level/between-stops, matching mission_story_steps' own convention.
  stop_id uuid references public.mission_stops(id) on delete cascade,
  step_order integer not null default 0,
  content_type text not null default 'talk'
    check (content_type in
      ('talk', 'image', 'audio', 'video', 'ponder', 'riddle', 'question',
       'clue', 'map', 'inspect', 'choice', 'discovery')),
  -- Admin-facing label only, never shown to players.
  title text not null,
  -- Null resolves to "the active local_guide character" at read time,
  -- same as game_guide_steps.character_id.
  character_id uuid references public.mission_characters(id) on delete set null,
  script text,
  audio_url text,
  avatar_video_url text,
  heygen_video_id text,
  -- draft | script_approved | audio_generated | video_generated | ready | published
  production_status text not null default 'draft',
  -- IMAGE / INSPECT content types.
  image_url text,
  -- RIDDLE / QUESTION content types -- reuses an existing mission_puzzles
  -- row (its own hint1/2/3/answer_reveal_text/hint_xp_penalty) rather than
  -- duplicating that shape here.
  puzzle_id uuid references public.mission_puzzles(id) on delete set null,
  -- CLUE / MAP / DISCOVERY content types.
  unlocks_map_piece_id uuid references public.mission_map_pieces(id) on delete set null,
  -- CHOICE content type: [{"label": "...", "response": "..."}]. Does NOT
  -- branch the route or mission graph -- no such infrastructure exists in
  -- this app; each option is a label + a follow-up line only.
  choice_options jsonb not null default '[]'::jsonb,
  -- mission_start | distance_from_destination | arrival | qr_scan |
  -- manual_discovery | previous_step_complete | map_piece_collected | puzzle_solved
  trigger_type text not null default 'manual_discovery',
  trigger_distance_meters double precision,
  required_previous_guide_step_id uuid references public.guide_steps(id) on delete set null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists guide_steps_mission_idx on public.guide_steps(mission_id, step_order);
create index if not exists guide_steps_stop_idx on public.guide_steps(stop_id);

alter table public.guide_steps enable row level security;
do $$
begin
  execute 'create policy "guide_steps_read" on public.guide_steps for select to anon, authenticated using (true)';
  execute 'create policy "guide_steps_write" on public.guide_steps for all to authenticated using (true) with check (true)';
end $$;

comment on column public.guide_steps.trigger_type is
  'mission_start | distance_from_destination | arrival | qr_scan | manual_discovery | previous_step_complete | map_piece_collected | puzzle_solved -- evaluated on-demand when the player opens the Guide tab (pull model), never a live background trigger engine.';
