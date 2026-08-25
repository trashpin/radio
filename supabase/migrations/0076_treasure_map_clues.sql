-- Marion County Adventures — TREASURE MAP + CLUE LAYER.
--
-- A second, secondary layer alongside the existing navigation map
-- (JourneyMap/AdventureMapScreen, completely untouched): a per-adventure
-- "treasure map" that assembles from discrete unlockable pieces, plus a
-- "Clues Found" collection of individually-typed discovery items.
--
-- Deliberately NOT a new trigger/progress system. Clue "found" state is
-- derived entirely from mission_progress.fired_content_ids (travel
-- stories) and mission_progress.unlocked_old_world_ids (Old Worlds) --
-- both already written by ActiveMissionController today. This migration
-- only adds: (1) the map pieces themselves, and (2) clue-classification
-- columns on the authoring table and the two runtime tables the live
-- engine already fires from, so StoryStepPublisher can copy them through
-- unchanged.

create table if not exists public.mission_map_pieces (
  id uuid primary key default gen_random_uuid(),
  mission_id uuid not null references public.missions(id) on delete cascade,
  piece_order integer not null default 0,
  title text not null,
  image_url text,
  created_at timestamptz not null default now()
);

create index if not exists mission_map_pieces_mission_idx on public.mission_map_pieces(mission_id, piece_order);

alter table public.mission_map_pieces enable row level security;
do $$
begin
  execute 'create policy "mission_map_pieces_read" on public.mission_map_pieces for select to anon, authenticated using (true)';
  execute 'create policy "mission_map_pieces_write" on public.mission_map_pieces for all to authenticated using (true) with check (true)';
end $$;

do $$
begin
  alter table public.mission_story_steps
    add column if not exists is_clue boolean not null default false,
    add column if not exists clue_type text,
    add column if not exists clue_image_url text,
    add column if not exists unlocks_map_piece_id uuid references public.mission_map_pieces(id) on delete set null;

  alter table public.mission_travel_stories
    add column if not exists is_clue boolean not null default false,
    add column if not exists clue_type text,
    add column if not exists clue_image_url text,
    add column if not exists unlocks_map_piece_id uuid references public.mission_map_pieces(id) on delete set null;

  alter table public.old_worlds
    add column if not exists is_clue boolean not null default false,
    add column if not exists clue_type text,
    add column if not exists clue_image_url text,
    add column if not exists unlocks_map_piece_id uuid references public.mission_map_pieces(id) on delete set null;
end $$;

alter table public.mission_story_steps
  add constraint mission_story_steps_clue_type_check
  check (clue_type is null or clue_type in
    ('image', 'audio', 'text', 'video', 'riddle', 'map_fragment', 'character_message'));
alter table public.mission_travel_stories
  add constraint mission_travel_stories_clue_type_check
  check (clue_type is null or clue_type in
    ('image', 'audio', 'text', 'video', 'riddle', 'map_fragment', 'character_message'));
alter table public.old_worlds
  add constraint old_worlds_clue_type_check
  check (clue_type is null or clue_type in
    ('image', 'audio', 'text', 'video', 'riddle', 'map_fragment', 'character_message'));

comment on column public.mission_travel_stories.is_clue is
  'True when this beat is also a Treasure Map discovery item, shown in the Clues Found list once its id appears in mission_progress.fired_content_ids.';
comment on column public.old_worlds.is_clue is
  'True when this reveal is also a Treasure Map discovery item, shown in the Clues Found list once its id appears in mission_progress.unlocked_old_world_ids.';
comment on column public.mission_map_pieces.image_url is
  'The fragment art shown once found. Never sent to the client for a locked (not-yet-found) piece.';
