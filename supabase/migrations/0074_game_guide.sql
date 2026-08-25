-- Marion County Adventures — THE GUIDE, a permanent Game Guide character.
--
-- The Guide's identity (name/image/personality/ElevenLabs voice/HeyGen
-- avatar) is NOT a new table -- it's just a `mission_characters` row with
-- character_type = 'local_guide' (already a suggested type in that
-- table's own free-text vocabulary). This migration adds only the two
-- things that don't already exist:
--   1. game_guide_steps -- the Guide's own content (introduction +
--      tutorial beats + one observation moment), a sibling of
--      mission_story_steps deliberately NOT reused directly (that table
--      requires a mission_id; Guide content belongs to no mission) but
--      column-compatible with it wherever they overlap so the SAME
--      heygen-avatar edge function can generate video for either table
--      via a `table` parameter, without per-table branching.
--   2. explorer_profiles -- per-player onboarding state (has this player
--      finished meeting the Guide, have they "become an Explorer"),
--      mirroring mission_progress's self-only-RLS, per-user-row shape.

create table if not exists public.game_guide_steps (
  id uuid primary key default gen_random_uuid(),
  character_id uuid references public.mission_characters(id) on delete set null,
  step_order integer not null default 0,
  -- introduction | tutorial_message | tutorial_observation
  step_type text not null default 'tutorial_message'
    check (step_type in ('introduction', 'tutorial_message', 'tutorial_observation')),
  -- Admin-facing label only, never shown to players.
  title text not null,
  script text,
  audio_url text,
  avatar_video_url text,
  heygen_video_id text,
  -- draft | script_approved | audio_generated | video_generated | ready | published
  production_status text not null default 'draft',
  -- tutorial_observation only -- the "WHAT DO YOU NOTICE?" sample photo.
  sample_image_url text,
  -- tutorial_observation only -- the tappable details and the Guide's
  -- response to each: [{"label": "...", "response": "..."}].
  detail_options jsonb not null default '[]'::jsonb,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists game_guide_steps_order_idx on public.game_guide_steps(step_order);
create index if not exists game_guide_steps_character_idx on public.game_guide_steps(character_id);

create table if not exists public.explorer_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  -- not_started | introduction_started | introduction_completed | explorer_activated
  guide_status text not null default 'not_started'
    check (guide_status in
      ('not_started', 'introduction_started', 'introduction_completed', 'explorer_activated')),
  activated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id)
);

create index if not exists explorer_profiles_user_idx on public.explorer_profiles(user_id);

alter table public.game_guide_steps enable row level security;
alter table public.explorer_profiles enable row level security;

do $$
begin
  -- Content table: same read/write convention as mission_story_steps.
  execute 'create policy "game_guide_steps_read" on public.game_guide_steps for select to anon, authenticated using (true)';
  execute 'create policy "game_guide_steps_write" on public.game_guide_steps for all to authenticated using (true) with check (true)';

  -- Player state is personal data: self-only, matching mission_progress_self_all.
  execute 'create policy "explorer_profiles_self_all" on public.explorer_profiles for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id)';
end $$;

-- Seed content so the feature works end-to-end immediately -- every word
-- below is admin-editable afterward via the Game Guide admin page, never
-- hard-coded in the app.
insert into public.game_guide_steps (step_order, step_type, title, script)
values
  (0, 'introduction', 'Welcome, Explorer',
   'Welcome, Explorer. What you''re about to enter isn''t a tour -- it''s a search. '
   || 'All around Marion County are stories, places, clues, and pieces of history. '
   || 'Some are easy to find. Others have been hiding in plain sight. '
   || 'Your job isn''t simply to travel from one place to another -- you''ll need to listen, '
   || 'look closely, and remember what you discover, because something you hear at the '
   || 'beginning may become the key to solving something much later. '
   || 'You''ll follow trails. You''ll meet people from the past. You''ll solve riddles. '
   || 'You''ll make choices, and sometimes you''ll have to decide which path to take. '
   || 'Your map will guide you, but it won''t give you all the answers. That''s your job. '
   || 'So... are you ready to become an Explorer?'),
  (1, 'tutorial_message', 'Adventures', 'Choose a mystery, and follow it.'),
  (2, 'tutorial_message', 'Map', 'Your map shows where your current journey is taking you.'),
  (3, 'tutorial_message', 'Stories', 'Listen carefully. Information may become useful later.'),
  (4, 'tutorial_message', 'Clues', 'Not everything you hear is immediately important.'),
  (5, 'tutorial_message', 'Puzzles', 'Sometimes you''ll have to figure things out.'),
  (6, 'tutorial_message', 'Choices', 'Your decisions may change the path you take.'),
  (7, 'tutorial_message', 'QR Discoveries', 'When you find a marker, you may unlock something unexpected.'),
  (8, 'tutorial_message', 'Characters', 'Some people you''ll meet belong to the present. Others belong to the past.'),
  (9, 'tutorial_message', 'Treasure Maps', 'Sometimes GPS gets you close. After that, you''ll have to explore.'),
  (10, 'tutorial_message', 'Discoveries', 'Everything you uncover becomes part of your Explorer journal.'),
  (11, 'tutorial_message', 'And sometimes...', 'And sometimes, the answer is hiding in plain sight.'),
  (12, 'tutorial_observation', 'What do you notice?', 'What do you notice?')
on conflict do nothing;

update public.game_guide_steps
set detail_options = '[
  {"label": "The old bell", "response": "Exactly. Remember that -- you never know when a small detail might matter."},
  {"label": "The worn path", "response": "Good eye. Not every clue looks like a clue."},
  {"label": "The faded sign", "response": "Pay attention to that. Small things add up."}
]'::jsonb
where step_type = 'tutorial_observation' and title = 'What do you notice?';
