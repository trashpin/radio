# Discovery System Analysis (pre-implementation)

Analysis of the current Flutter architecture before building the **👀 I See
Something** *discovery guide* (an interactive wildlife/nature identification
experience). Goal: reuse existing structures; no duplicate models/repos/
services/providers/widgets.

> Note: an earlier "I See Something" **reporting** flow exists
> (`lib/features/sightings/`, the bottom sheet + `explorer_sightings` table).
> This new feature is a **discovery/identification guide**, which is different.
> The reporting flow is no longer wired into the Radio player (removed to match
> the player mockup); it will be repurposed as the **Journal / "Mark as seen"**
> capture path for discovery (reused, not replaced or duplicated).

## Existing building blocks to reuse
| Need | Existing (reuse) |
|---|---|
| Backend client | `SupabaseService`, `supabaseClientProvider` |
| Generic CRUD | `SupabaseReadRepository` / `SupabaseSyncRepository` |
| Species-ish content | `Wildlife` (`wildlife` table + `WildlifeRepository`), `Plant` (`plants`) |
| Media / images / audio | `MediaItem` + `MediaRepository` (photos/audio in `mp3` bucket) |
| Favorites | `UserFavorite` + `UserFavoriteRepository` + `favoritesProvider` |
| AI narration (placeholder) | `AiRangerNarrationService` (sightings) — extend for species narration |
| Journal / seen | `explorer_sightings` (repurpose for "seen"/journal) |
| Map (Where Found) | `MapsScreen` + `_circleIconMarker` |
| Design tokens / cards | `AppColors/Spacing/Radius`, `AppCard`, `DashboardCard` |

## Gaps (new, non-duplicating)
- A **unified species catalog** spanning all 17 categories (birds, trees,
  waterfalls, historic sites…). Today only `wildlife`/`plants` exist and only as
  models (tables not provisioned live). The discovery guide needs a broader
  `species` concept + category taxonomy.
- **Species detail data**: images gallery, audio narration, sounds
  (call/song/warning), facts, identification, comparisons, habitats/where-found,
  keywords for search.
- **User data**: favorites (exists), journal entries, seen species / life list.
- **Offline** packaging per downloaded park.

## Decision (avoid duplication)
- Introduce a `discovery` feature (`lib/features/discovery/`) with a **category
  taxonomy** and, going forward, a `Species` model that **generalizes**
  `Wildlife`/`Plant` (which become category-specific views over `species`),
  rather than adding parallel tables. New tables: `species`, `species_images`,
  `species_audio`, `species_facts`, `species_comparisons`, `species_habitats`,
  `species_sounds`, `species_keywords`, `journal_entries`, `seen_species`
  (favorites reuse `user_favorites`). Categories can be a table or the local
  taxonomy below.
- Reuse `MediaRepository`/storage for images/audio; reuse
  `AiRangerNarrationService` seam for "Hear About This"; reuse `favoritesProvider`.

## This phase (screen-by-screen)
Build the **Discovery Categories** screen (the provided mockup): the 17
category cards + "Popular in This Park" row, reached from a new Home card
("👀 I See Something — What did you discover today?"). Category → Species list →
Species detail → Compare are the subsequent screens (built as their designs come
in). Architecture/DB/offline/compare are documented now in the deliverable docs.

## Compatibility (to verify in self-review)
Explorer Home (new card), Map (Where Found layer), Explorer Radio (separate;
shares AI Ranger seam), AI Ranger (placeholder), Trips/Journal (seen/life list),
Supabase, Riverpod, repository pattern.
