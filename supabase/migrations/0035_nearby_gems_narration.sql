-- ExplorerOS — Nearby Gems narrated storytelling
--
-- Adds a dedicated NARRATION SCRIPT to each Nearby Gem so gems can be voiced by
-- the existing ElevenLabs pipeline (admin "Generate Narration") and narrated on
-- the ExplorerOS Radio "Now Playing" view when a traveler taps a gem.
--
-- Field roles after this migration:
--   short_description  – one-liner shown on cards
--   long_story         – the Long Description (rich detail / fallback narration)
--   narration_script   – the exact spoken script (fed to ElevenLabs / on-device TTS)
--   narration_url      – the prerecorded/generated audio (played first when present)
--
-- Idempotent: safe to re-run.

alter table public.nearby_gems
  add column if not exists narration_script text;
