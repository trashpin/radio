-- Marion County Adventures — mystery/puzzle refinement layer.
--
-- This does NOT build an AI puzzle-generation system or a full character/
-- voice-management system (both explicitly deferred) -- it adds the data
-- structure so story content can be tagged with facts a later puzzle draws
-- on, and so a puzzle/final-reveal moment can exist at all. Difficulty's
-- CHECK constraint is dropped (was 'easy'/'moderate'/'hard') in favor of
-- free text, matching `category`'s existing philosophy -- the vocabulary
-- ('easy'/'adventure'/'challenge'/'master' per this spec) is still
-- evolving and a rigid constraint would need a migration every time it
-- changes.

alter table public.missions drop constraint if exists missions_difficulty_check;
alter table public.missions
  add column if not exists mission_brief_text text,   -- "YOUR MISSION: find the journal..."
  add column if not exists intro_character_name text, -- who speaks the adventure introduction
  add column if not exists final_reveal_text text;     -- "YOU SOLVED IT... " shown at completion

-- A story beat can now name its speaker and reveal one or more named facts
-- the player may need to recall later. `voice_id` is an optional ElevenLabs
-- voice override (the shared discover-narration function already falls
-- back to the global default voice when this is null) -- the minimal seam
-- needed for "each character should eventually have an associated voice"
-- without building character/voice management yet.
alter table public.mission_travel_stories
  add column if not exists speaker_name text,
  add column if not exists voice_id text,
  add column if not exists reveals_fact_keys text[] not null default '{}';

alter table public.old_worlds
  add column if not exists voice_id text,
  add column if not exists reveals_fact_keys text[] not null default '{}';

-- A named piece of information the story reveals — the player may not know
-- why it matters yet. `key` is the stable id a puzzle's
-- `related_fact_keys` references; `label`/`value` are what the story
-- actually said, kept verbatim rather than re-derived.
create table if not exists public.mission_facts (
  id uuid primary key default gen_random_uuid(),
  mission_id uuid not null references public.missions(id) on delete cascade,
  key text not null,
  label text not null,
  value text not null,
  created_at timestamptz not null default now(),
  unique (mission_id, key)
);

-- A test of attention/reasoning. `type` intentionally stays free text
-- (memory/observation/deduction/history/code/connection/direction per this
-- spec, or a future type) rather than a fixed enum -- only a subset needs
-- real runtime support today; the schema is ready for the rest. Answer
-- checking is a simple case-insensitive/trimmed match against
-- `accepted_answers` -- not an AI grader.
create table if not exists public.mission_puzzles (
  id uuid primary key default gen_random_uuid(),
  mission_id uuid not null references public.missions(id) on delete cascade,
  stop_id uuid references public.mission_stops(id) on delete cascade, -- null = mission-level/final puzzle
  type text not null default 'memory',
  prompt text not null,
  accepted_answers text[] not null default '{}',
  hint text,
  success_text text,
  related_fact_keys text[] not null default '{}',
  reward_xp integer not null default 0,
  sequence integer not null default 0,
  created_at timestamptz not null default now()
);

-- Which facts the player has actually heard, and which puzzles they've
-- already solved — per-player state, mirroring `fired_content_ids`' role
-- for travel stories.
alter table public.mission_progress
  add column if not exists revealed_fact_keys text[] not null default '{}',
  add column if not exists solved_puzzle_ids uuid[] not null default '{}';

create index if not exists mission_facts_mission_idx on public.mission_facts(mission_id);
create index if not exists mission_puzzles_mission_idx on public.mission_puzzles(mission_id);
create index if not exists mission_puzzles_stop_idx on public.mission_puzzles(stop_id);

alter table public.mission_facts enable row level security;
alter table public.mission_puzzles enable row level security;
do $$
begin
  execute 'create policy "mission_facts_read" on public.mission_facts for select to anon, authenticated using (true)';
  execute 'create policy "mission_facts_write" on public.mission_facts for all to authenticated using (true) with check (true)';
  execute 'create policy "mission_puzzles_read" on public.mission_puzzles for select to anon, authenticated using (true)';
  execute 'create policy "mission_puzzles_write" on public.mission_puzzles for all to authenticated using (true) with check (true)';
end $$;
