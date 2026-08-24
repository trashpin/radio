-- Tracks a story step's in-flight/most-recent HeyGen render job id, so the
-- `heygen-avatar` edge function's "status" action knows which HeyGen video
-- to poll for a given step.

alter table public.mission_story_steps
  add column if not exists heygen_video_id text;
comment on column public.mission_story_steps.heygen_video_id is
  'The HeyGen render job id while an avatar video is processing -- polled by the heygen-avatar edge function''s "status" action, then cleared/kept for reference once avatar_video_url is set from our own mirrored copy in the videos storage bucket.';
