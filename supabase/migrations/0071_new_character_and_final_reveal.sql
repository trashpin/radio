-- Marion County Adventures — QR discoveries can introduce a new historical
-- character, and adventures get a real, connected ending. Purely additive:
-- no existing mission/location/character records touched, no GPS/trigger
-- logic changed.

-- A QR discovery ("ENTER THE OLD WORLD") can now visually introduce a new
-- character (avatar video), not just narrate text — the same avatar
-- pipeline missions.opening_video_url already uses, applied to old_worlds.
alter table public.old_worlds
  add column if not exists character_video_url text;
comment on column public.old_worlds.character_video_url is
  'Avatar video (HeyGen) for the character who appears at this Old World reveal -- "a NEW CHARACTER APPEARS," not just another narrated info page. Published from a qr/old_world/discovery-type mission_story_steps row. Null falls back to the character''s static image + audio-only narration.';

-- The Story Production System (mission_story_steps) had no way to mark
-- which mission_facts a step reveals -- meaning the "plant a detail early,
-- pay it off later" mechanic could only be wired through the OLDER
-- mission_travel_stories/old_worlds admin pages, not the newer Story
-- Builder. This closes that gap.
alter table public.mission_story_steps
  add column if not exists reveals_fact_keys text[] not null default '{}';
comment on column public.mission_story_steps.reveals_fact_keys is
  'Named mission_facts.key values this step reveals when it plays -- the player may not know why yet. Published into mission_travel_stories.reveals_fact_keys or old_worlds.reveals_fact_keys depending on step_type.';

-- The adventure's real ending: reconnects an early detail with what the
-- player eventually learns (missions.hero_image_url is shown again at
-- Mission Complete for exactly this reason), optionally delivered by the
-- same avatar system as the introduction, plus a clearly-separated
-- historical-accuracy disclosure.
alter table public.missions
  add column if not exists final_reveal_video_url text,
  add column if not exists real_history_text text;
comment on column public.missions.final_reveal_video_url is
  'Avatar video (HeyGen) delivering the Final Reveal -- mirrors opening_video_url''s role at the start of the adventure. Published from a final_reveal-type mission_story_steps row. Null falls back to final_reveal_text shown as plain text.';
comment on column public.missions.real_history_text is
  '"THE REAL HISTORY" -- a mission-level disclosure, separate from the dramatic final_reveal_text, stating what is historically verified, what source/document/photo supports it, what was fictionalized for the adventure, and why the historical evidence matters. Complements the per-Old-World is_fictional flag with one closing, whole-adventure statement.';
