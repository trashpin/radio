# Flutter ↔ Base44 Data Gap Report

Compares the live Base44/Supabase schema (`DATABASE_MAP.md`) against the Flutter
app's models/repositories/providers. Goal: reuse existing structures, fix
mismatches, and avoid duplicates.

## Legend
✅ connected & aligned · ⚠️ exists but misaligned (must fix) · ➕ missing (add) ·
🚫 Flutter-defined but no Base44 table (unused/roadmap) · ♻️ duplicate concept

## Per-entity status

| Base44 table | Flutter model | Repository | Provider | Status |
|---|---|---|---|---|
| `destinations` | `Destination` | `DestinationRepository` | `destinationsProvider` | ✅ aligned (Option A) |
| `media` | `MediaItem` | `MediaRepository` | `mediaRepositoryProvider` | ✅ aligned |
| `stops` | `Stop` | `StopRepository` | `stopsByParkProvider` | ⚠️ **misaligned** — model reads `id/park_id/name/image_url/order_index`; Base44 uses `stop_id/destination_id/stop_name/hero_image/sort_order` |
| `stories` | `Story` | `StoryRepository` | `storiesByParkProvider` | ⚠️ **misaligned** — model reads `id/park_id/body/image_url`; Base44 uses `story_id/destination_id/full_story/voice_script/hero_media_id` |
| `knowledge_articles` | — | — | — | ➕ **missing** model/repo/provider |
| `narrations` | `Narration` | `NarrationRepository` | `narrationsByStory…` | 🚫 Base44 `narrations` is a placeholder (unusable/empty) |
| `radio` (dict) | — | — | — | not app data (schema dictionary) |
| `visitor`, `visitor_csv_data` | — | — | — | not app data (import artifacts) |

## Missing (to add)
- **Model:** `KnowledgeArticle` (for `knowledge_articles`).
- **Repository:** `KnowledgeArticleRepository` (+ `SupabaseTables.knowledgeArticles`).
- **Providers:** destination-scoped list providers keyed on `destination_id`
  (existing stop/story providers key on the non-existent `park_id`).

## Misaligned (to fix — reuse existing, do NOT duplicate)
- **`Stop`** — remap `fromJson` to Base44 columns (`stop_id`, `destination_id`,
  `stop_name`, `hero_image`, `sort_order`, `latitude/longitude`, plus
  `stop_type`, `audio_available`, `gps_trigger_radius_meters`). Keep the same
  class/field surface; add fallbacks so seed/preview data still parses.
- **`Story`** — remap `fromJson` (`story_id`, `destination_id`, `title`,
  `full_story`/`short_summary` → `body`, `voice_script`, `story_category`,
  `hero_media_id`). Keep the class; add fallbacks.
- **`StopRepository` / `StoryRepository`** relationship queries: switch from
  `park_id` to `destination_id` (Base44 has no `park_id`).

## Flutter-defined but NOT in Base44 (unused / roadmap) 🚫
`parks`, `wildlife`, `plants`, `songs`, `radio_stations`, `announcements`,
`station_rules`, `station_profiles`, `gps_audio_triggers`, `playback_history`,
`park_boundaries`, `state_boundaries`, `county_boundaries`, `location_history`,
`travel_sessions`, `albums`, `genres`, `moods`, `artworks`, `music_metadata`,
`playlists`, `station_assignments`, `gps_music_triggers`, `upload_jobs`,
`user_favorites`, `downloads`.

These have Flutter models/repos but **no live table** → they will read empty and
should stay as roadmap until their tables are created by migration. **Do not
create duplicates** of them for Base44; instead create their tables when needed.

## Duplicate concepts ♻️ (avoid)
- **`Park`/`parks` vs `destinations`** — Base44 has **no `parks` table**;
  "parks" IS `destinations`. The `Park` model + `ParkRepository` duplicate the
  destination concept. Keep using `Destination`; treat `Park` as legacy. Do not
  wire `Park` to Base44.
- **`Song`/`songs` vs `media`(audio)** — audio already comes from `media` (via
  `MediaItem.toSong`). The separate `Song`/`songs` path targets a non-existent
  table; prefer the `media`-backed path.

## Plan (Step 4)
1. Align `Stop` + `Story` `fromJson` to Base44 (reuse the classes).
2. Add `KnowledgeArticle` model + repo + `knowledgeArticles` table constant.
3. Repoint stop/story relationship queries + add destination-scoped providers.
4. Verify each with unit tests (Base44-shaped JSON) + live reachability.
