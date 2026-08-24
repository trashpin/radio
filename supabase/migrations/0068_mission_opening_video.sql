-- Connects the Story Production System's avatar video generation to what a
-- player actually sees: a mission_introduction-type story step's
-- avatar_video_url had nowhere to publish TO -- the `missions` table only
-- had text/audio fields for the Adventure Introduction. This is the
-- missing link so "Publish" on that step type actually makes the
-- character's video play when a player selects the adventure.

alter table public.missions
  add column if not exists opening_video_url text;
comment on column public.missions.opening_video_url is
  'The character avatar video (HeyGen, mirrored into the videos storage bucket) shown at the top of the Adventure Introduction screen, before any map/GPS begins. Published from a mission_introduction-type mission_story_steps row. Null falls back to the existing static character image + audio-only narration.';
