# Radio UI Architecture

How the flagship Explorer Radio experience is structured and how the
"I See Something" action integrates. Companion: `RADIO_UI_ANALYSIS.md`,
`SIGHTING_SYSTEM_ARCHITECTURE.md`.

## Folder structure (relevant)
```
lib/features/radio/
  presentation/radio_screen.dart      # the player UI (dark, automotive feel)
  controllers/radio_engine_controller.dart
  services/…                          # engine, schedulers, audio adapter
  providers/radio_session_provider.dart
lib/features/sightings/               # the "I See Something" system (see other doc)
```

## Radio screen
`RadioScreen` → `radioSessionProvider` (station + playlist) and
`radioEngineControllerProvider` (live `PlaybackState`). Components:
- Wordmark header, `FLORIDA EXPLORER` label, station title + `LIVE` badge.
- Vinyl artwork (rotates while playing), skip‑15 controls.
- Track title + subtitle + favorite.
- **"I SEE SOMETHING"** button (`_ReportButton`) → opens the sighting sheet
  with the current station's destination as auto‑captured location.
- Progress bar (`_TrackProgress`), transport row (shuffle/prev/**gold play**/
  next/repeat), `UP NEXT` card.

## Playback flow
```
radioSessionProvider: destinations → pick destination w/ audio media
  → RadioStation.fromDestination + media.songsForDestination
  → RadioEngineService.changeStation(songs)
User taps Play → RadioEngineController.play() → RadioEngineService → RadioAudioService (just_audio)
Engine events → controller republishes PlaybackState → UI updates (title, progress)
```
Verified live end‑to‑end (a Base44‑imported song, "Ocala Better", plays).

## Stations
Stations are derived from Supabase `destinations` today (one station per
destination, playlist from its audio `media`). "Country Roads / Rock Trails /
Today's Hits / Kids Adventure" are content/curation (station rows or curated
playlists) to be authored in Base44 — the loader is already dynamic
(`destinations` → stations), so adding them is a data task, not a code change.
A dedicated `radio_stations` table + station selector UI is the next step.

## "I See Something" integration
The existing button is the single entry point (no duplicate control). It builds
a `SightingContext` from the current station's `Destination` (park + coords) and
calls `showISeeSomethingSheet(...)`. Everything else lives in the sightings
feature (see `SIGHTING_SYSTEM_ARCHITECTURE.md`).

## Future AI narration
`SightingNarrationService` (placeholder, no OpenAI/ElevenLabs) is the seam for
AI reactions to sightings; the radio engine's `requestInterruption(segment)`
already supports injecting narration between songs, so future AI Ranger audio
can be ducked over music without UI changes.

## Not changed
The radio engine, audio adapter, GPS engine, and Map engine are untouched —
this work only adds the sighting entry point and a map marker layer.
