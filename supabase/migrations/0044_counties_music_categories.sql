-- CountyConfig as single source, Phase C: a county's preferred music genres.
--
-- The Smart Music Rotation engine (smart_music_rotation.dart) scores songs by
-- park, attraction, time of day, season, tags, mood, etc. — but had no county
-- dimension. This adds an admin-editable list of music categories per county
-- (e.g. Marion → country/americana/southern/florida); the rotation gives songs
-- a bonus when their tags overlap the current county's categories.
--
-- Matches the existing array-column pattern on this table (recommendations
-- text[]). Additive + idempotent.

alter table public.counties
  add column if not exists music_categories text[] default '{}';
