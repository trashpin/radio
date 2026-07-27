-- ============================================================================
-- ExplorerOS optional example seed data
-- ----------------------------------------------------------------------------
-- Safe + idempotent (ON CONFLICT DO NOTHING). Run AFTER 0019_backend_foundation.
-- Only touches net-new tables, so it will not disturb existing production rows.
-- ============================================================================

-- Achievements a new explorer can earn.
insert into public.achievements (code, title, description, icon) values
  ('first_story',  'First Listen',   'Play your first GPS story.',           'headphones'),
  ('explorer_10',  'Trailblazer',    'Visit 10 destinations.',               'map'),
  ('night_owl',    'Night Owl',      'Listen to the radio after sunset.',    'moon'),
  ('collector',    'Collector',      'Bookmark 25 places.',                  'bookmark')
on conflict (code) do nothing;

-- A default DJ voice profile (fill in voice_id with your ElevenLabs voice).
insert into public.voice_profiles (name, provider, gender, personality, language, active)
select 'DJ Brittney', 'elevenlabs', 'female', 'warm, upbeat radio host', 'en', true
where not exists (select 1 from public.voice_profiles where name = 'DJ Brittney');

-- Feature flags (also seeded by the migration; harmless to re-assert).
insert into public.feature_flags (key, enabled, description) values
  ('dj_banter',     true,  'DJ talks between songs'),
  ('gps_stories',   true,  'GPS-triggered story playback'),
  ('ai_generation', true,  'AI research/story/audio generation'),
  ('translations',  false, 'Multi-language narration')
on conflict (key) do nothing;
