# Discovery System Architecture — 👀 I See Something

Interactive wildlife/nature identification guide. Companion docs:
`DISCOVERY_SYSTEM_ANALYSIS.md`, `SPECIES_DATABASE.md`, `COMPARE_SYSTEM.md`,
`OFFLINE_STRATEGY.md`.

## Folder structure
```
lib/features/discovery/
  models/
    discovery_category.dart      # 17-category taxonomy (label/subtitle/icon/color)  ✅ built
    species.dart                 # unified species model (roadmap)
    species_detail.dart          # images/audio/facts/comparisons (roadmap)
  data/
    species_repository.dart      # reads species by category/park + search (roadmap)
    species_detail_repository.dart
  services/
    species_narration_service.dart   # "Hear About This" (reuses AiRanger placeholder)
    life_list_service.dart            # favorites/seen/journal (reuses user_favorites + explorer_sightings)
  providers/
    discovery_providers.dart     # categories, popular-in-park, search, favorites
  presentation/
    discovery_categories_screen.dart  # the grid  ✅ built
    category_species_screen.dart      # list: search/alphabet/recent/favorites/grid (next)
    species_detail_screen.dart        # hero/gallery/sections/sounds/where-found (next)
    compare_screen.dart               # swipeable comparison cards (next)
```
Entry: a Home `DashboardCard` ("I See Something — What did you discover today?")
pushes `/discover` (route added). Category → species list → detail → compare.

## Navigation
`/discover` (categories) → push category species list → push species detail →
push compare. All pushed (full-screen) over the shell; reuses `go_router` +
`Navigator.push` for deep screens. Deep-linkable by `species_id`/category token.

## Database
See `SPECIES_DATABASE.md`. Core: `species` (generalizes `wildlife`/`plants`) +
`species_images/audio/sounds/facts/comparisons/habitats/keywords`, plus user
data (`user_favorites` reused, `journal_entries`, `seen_species`). Categories =
the local taxonomy (or an optional `categories` table).

## Data flow
```
Supabase ── repositories ── Riverpod providers ── screens
             (reuse SupabaseReadRepository; MediaRepository for images/audio)
Popular-in-park: species filtered by park presence (species_habitats)
Search: species_keywords + name ILIKE across categories
```

## Audio ("Hear About This" + sounds)
- Narration: `species_narration_service` — placeholder now (reuses the
  `AiRangerNarrationService` seam); future ElevenLabs TTS routed through the
  existing `AudioPlayerPort`/`RadioAudioService` so it can duck radio music.
- Species sounds (call/song/warning): stored in `species_sounds` (audio in the
  `mp3`/a `species_audio` bucket); a waveform animation plays over the clip.

## Future AI integration
- **AI Vision / camera identification:** a `SpeciesIdentificationService` seam
  (image → candidate species) calling a Supabase Edge Function (server-side key).
- **Ask AI Ranger:** the existing AI Ranger placeholder → OpenAI + ElevenLabs
  voice via Edge Function.
- **Voice search / offline AI:** search provider abstracts the query source.

## Reuse (no duplication)
`SupabaseService`, generic repositories, `MediaRepository` (images/audio),
`favoritesProvider`/`user_favorites`, `AiRangerNarrationService`, `MapsScreen`
(Where Found), design tokens + `AppCard`/`DashboardCard`.
