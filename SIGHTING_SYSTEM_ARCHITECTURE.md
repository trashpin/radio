# Sighting System Architecture ("I See Something")

Citizen-science observation capture, storage, AI reaction, map display, and
admin management. Built with the repository pattern + Riverpod + services, all
reusing the app's existing Supabase connector (no duplicate connections).

## Folder structure
```
lib/features/sightings/
  models/
    sighting_category.dart        # enum: 14 categories (token/label/icon)
    explorer_sighting.dart        # model (+ fromJson/toJson) → explorer_sightings
  data/
    sighting_repository.dart      # reads (cached) + create/delete (PK = sighting_id)
  services/
    ai_ranger_narration_service.dart   # placeholder AI reaction (no LLM/TTS)
    sighting_service.dart              # orchestrates save + reaction (graceful)
  providers/
    sighting_providers.dart       # recentSightings (AsyncNotifier) + byDestination
  presentation/
    i_see_something_sheet.dart    # bottom sheet: form + confirmation/AI reaction
lib/features/admin/presentation/sightings_page.dart   # admin: list/search/filter/delete/export
supabase/migrations/0003_explorer_sightings.sql       # tables + RLS
```

## Database schema (`0003_explorer_sightings.sql`)
- **`explorer_sightings`** — `sighting_id` (uuid PK, default gen_random_uuid()),
  `user_id`, `category` (not null), `species`, `notes`, `latitude`, `longitude`,
  `elevation_ft`, `destination_id` (FK → destinations), `park_name`, `trail`,
  `travel_direction`, `weather`, `photo_url` (future), `created_at` (default now()).
  Indexed on destination/category/created_at. RLS demo-open (read/insert/delete
  for anon+authenticated) — tighten to auth/roles later.
- **`sighting_categories`** — reference table seeded with the 14 categories
  (future-ready; the app also has a local enum).
- Not created (future): `sighting_photos`, species identification tables.

## Sighting workflow
```
Radio "I See Something" → showISeeSomethingSheet(location: SightingContext)
  Sheet: pick category (grid) · species (search field) · notes · recent picker
         · auto-captured location strip (park + coords + time)
  Save → SightingService.report(draft):
     repo.create(draft)  ─ success ─▶ persisted row (DB id + created_at)
                          ─ failure ─▶ kept locally (e.g. table not yet created)
     AiRangerNarrationService.reactTo(...) → "Great find! That appears to be a …"
     recentSightingsProvider.add(sighting)  (optimistic)
  Confirmation view: ✓ logged + AI Ranger reaction + Done
Map: recentSightingsProvider → amber "visibility" markers (category + notes)
Admin → Explorer Sightings: search/filter-by-category/delete/export CSV
```
Location is auto-captured best-effort from the current destination (park +
coords); `elevation/trail/direction/weather` are placeholders until the GPS
engine supplies a live fix (seam already present via `SightingContext`).

## Reuse (no duplication)
- Supabase: `SupabaseService` client + `SupabaseReadRepository` base (reads).
- Map: existing `MapsScreen` + `_circleIconMarker` bitmap helper (added a layer).
- Admin: existing shell + module catalog (added one `explorerSightings` module).
- AI Ranger: extends the placeholder companion concept; no new engine.

## Future-ready seams
- **AI identification / ElevenLabs narration:** implement inside
  `AiRangerNarrationService` (swap the canned reaction for LLM text + TTS audio;
  route audio through `RadioEngineService.requestInterruption`).
- **Photos:** `photo_url` column + a `sighting_photos` table + upload via the
  existing `MusicStorageService` pattern to a `sighting_photos` bucket.
- **Community / life lists / badges / rare-species alerts:** all derive from the
  `explorer_sightings` table (add read models/queries; no schema change to the
  core row beyond optional joins).
- **Offline submissions:** the service already degrades gracefully (keeps the
  sighting locally on save failure) — persist a local queue and sync later.
