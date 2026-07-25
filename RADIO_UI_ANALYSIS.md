# Radio UI Analysis (pre-implementation)

Analysis of the existing Radio, GPS, AI Ranger, and Map architecture **before**
building the flagship Explorer Radio + "I See Something" sighting system. Goal:
extend, not replace; no duplicate models/providers/services.

## Explorer Radio (existing)
- **UI:** `lib/features/radio/presentation/radio_screen.dart` — dark premium
  player: wordmark, `FLORIDA EXPLORER` label, station title + `LIVE` badge,
  vinyl artwork, track title/subtitle, **an existing "I SEE SOMETHING" button
  (`_ReportButton`, currently a snackbar stub)**, progress bar (`_TrackProgress`),
  transport row (shuffle/prev/**gold play**/next/repeat), and an `UP NEXT` card.
- **State/engine:** `RadioEngineController` (`radioEngineControllerProvider`) →
  `RadioEngineService` (decision engine) + `RadioAudioService` (just_audio).
  Session bootstrap: `radioSessionProvider` (derives station from a
  `destination` + loads audio from `media`). Playback verified live ("Ocala
  Better").
- **Reuse for this task:** upgrade the existing `_ReportButton` to open the
  sighting sheet (do NOT add a second button/flow). Keep the engine untouched.

## GPS engine (existing)
- `GPSService` (`gpsServiceProvider`), `gpsControllerProvider`, and a rich
  `TravelContext` (`lib/features/gps/models/travel_context.dart`) with current
  destination/park, GPS location, heading, etc. `TravelCompanionService`
  integrates GPS ↔ Producer ↔ Radio.
- **Reuse:** location capture for a sighting should read the current
  destination/coords (from the active station's `Destination`) with an optional
  GPS hook — do NOT reimplement positioning. On web there is usually no live
  fix, so capture is best-effort (park + coords from the current destination;
  elevation/heading/weather = placeholders).

## AI Ranger (existing)
- `AiRangerScreen` placeholder + `companion` feature (`TravelCompanionService`).
  No LLM/TTS integration (correct — none wanted yet).
- **Add (not duplicate):** a `SightingNarrationService` **placeholder** that
  returns a canned reaction ("Great find! That appears to be a …"). It is the
  seam for future OpenAI/ElevenLabs — no external calls.

## Map engine (existing)
- `MapsScreen` — `google_maps_flutter` hybrid map plotting destinations as
  circular icon markers, with a nearest-place card and floating controls.
- **Reuse:** add a **sightings marker layer** to the existing `MapsScreen`
  (category-icon markers with title/snippet). Reuse the existing
  `_circleIconMarker` bitmap approach; do NOT create a second map.

## Music Library / Media (existing)
- `media` table + `MediaRepository`; audio plays from `file_url`. Sightings are
  a separate domain (no overlap) — a new `explorer_sightings` table.

## Supabase (existing)
- Single client (`SupabaseService`), generic `SupabaseReadRepository` /
  `SupabaseSyncRepository` (upsert/delete). RLS: content tables need explicit
  anon read policies (added for destinations/stops/stories/knowledge).
- **Add:** an `explorer_sightings` table (+ optional `sighting_categories`) via
  migration. Reuse `SupabaseSyncRepository` for CRUD (write path).

## What already exists → what to add (no duplication)
| Need | Existing (reuse) | New (add) |
|---|---|---|
| Report button | `_ReportButton` in radio_screen | upgrade to open sheet |
| Playback | RadioEngine + controller | — |
| Location | `TravelContext` / current `Destination` | `SightingContext` capture (best-effort) |
| AI reaction | AiRanger placeholder | `SightingNarrationService` (placeholder) |
| Map | `MapsScreen` + `_circleIconMarker` | sightings marker layer |
| CRUD | `SupabaseSyncRepository` | `SightingRepository`, `ExplorerSighting` model |
| Admin | admin shell + module catalog | `Explorer Sightings` module + page |

## Plan
1. Models: `SightingCategory` enum, `ExplorerSighting` (+ `explorerSightings` table const).
2. Data/services: `SightingRepository` (sync), `SightingNarrationService`
   (placeholder), `SightingService`, providers (recent + by destination + draft).
3. UI: `ISeeSomethingSheet` (categories grid, species, notes, recent, auto
   location, AI reaction, save/cancel) + reusable opener; wire the Radio button.
4. Map: sightings layer. Admin: `Explorer Sightings` list (search/filter/delete/export).
5. Migration `0003_explorer_sightings.sql`. Docs + self-review.
