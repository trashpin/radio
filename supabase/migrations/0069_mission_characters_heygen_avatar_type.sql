-- A character's heygen_avatar_id alone is ambiguous: HeyGen's stock/studio
-- avatars (avatar_id) and custom photo avatars an admin trains directly in
-- HeyGen (talking_photo_id) use different request shapes in HeyGen's own
-- API and are not interchangeable. Sending the wrong shape either errors
-- or silently renders the wrong/default character. This column records
-- which shape a character's id is, so the heygen-avatar edge function
-- always builds the correct request.

alter table public.mission_characters
  add column if not exists heygen_avatar_type text not null default 'talking_photo';
comment on column public.mission_characters.heygen_avatar_type is
  'Which HeyGen character shape heygen_avatar_id is: "avatar" for a stock/studio avatar_id, "talking_photo" for a custom photo avatar (talking_photo_id) -- these use different request shapes in the HeyGen API and are not interchangeable.';
