-- Marion County Adventures — PROGRESSIVE GUIDE HINT SYSTEM.
--
-- mission_puzzles already backs BOTH puzzle kinds (stop_id null = the
-- mission-level final puzzle; stop_id set = a stop-level "test of wits")
-- and already has ONE flat hint column. This adds two more levels plus an
-- answer-reveal teaching moment and a per-puzzle XP cost for using help —
-- purely additive, the existing `hint` column is kept as-is (treated as
-- "Hint 1" in the app) so no existing puzzle content or code path breaks.

alter table public.mission_puzzles
  add column if not exists hint2 text,
  add column if not exists hint3 text,
  add column if not exists answer_reveal_text text,
  add column if not exists hint_xp_penalty integer not null default 5;

comment on column public.mission_puzzles.hint is
  'Hint level 1 (NUDGE) — a subtle suggestion, never the answer.';
comment on column public.mission_puzzles.hint2 is
  'Hint level 2 (CLUE) — a stronger hint pointing toward the solution.';
comment on column public.mission_puzzles.hint3 is
  'Hint level 3 (GUIDE ME) — explains how to solve it without stating the final answer.';
comment on column public.mission_puzzles.answer_reveal_text is
  'Optional last-resort teaching moment: the answer PLUS why, never a bare '
  '"Answer: X." Only offered in the app after every available hint has been shown.';
comment on column public.mission_puzzles.hint_xp_penalty is
  'XP deducted from reward_xp per hint level used (admin-configurable, default 5). '
  'Revealing the answer awards 0 XP. Never blocks completing the adventure.';
