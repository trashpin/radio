# ExplorerOS-Mobile

Read-only Flutter mobile client for ExplorerOS destinations (National Park Buddy,
Florida Buddy, Historic Route 66, and future destinations). Destination content is
fetched at runtime from the backend (Supabase) — **never hardcode destinations**.

## Project layout (`lib/`)

- `main.dart` — entry point: initializes Supabase, wraps app in Riverpod `ProviderScope`.
- `app/app.dart` — root `MaterialApp.router` (theme + navigation).
- `core/constants/` — app-wide constants and backend env-var *names*.
- `core/theme/` — `app_colors.dart`, `app_typography.dart`, `app_theme.dart`.
- `core/error/` — `AppException` model + `ErrorHandler` (maps backend errors).
- `core/router/` — `go_router` config; `app_scaffold.dart` holds the bottom nav.
- `services/` — `supabase_service.dart` (single doorway to the backend).
- `models/` — read-only data models (e.g. `Destination`).
- `shared/widgets/` — reusable widgets (`LoadingWidget`, `ErrorView`, `ComingSoonView`).
- `features/<feature>/` — feature-first screens (home, destinations, map, radio, profile, settings).

## Standard commands

Run from repo root (see Flutter docs for details):

- Install deps: `flutter pub get`
- Lint: `flutter analyze`
- Test: `flutter test`
- Run (web): `flutter run -d chrome` (or a headless server, see below)

## Cursor Cloud specific instructions

- **Flutter SDK** is installed at `~/flutter` and added to `PATH` via `~/.bashrc`.
  If `flutter` is not found in a non-interactive shell, invoke it as
  `~/flutter/bin/flutter` or run `export PATH="$HOME/flutter/bin:$PATH"` first.
- Only the **web** toolchain is available here. The **Android SDK** and the
  **Linux desktop** toolchain (ninja/GTK) are NOT installed, so `flutter run`
  targeting Android/Linux will fail. Use web for verification.
- **Demoing the app in this VM** (no auto-launching browser device): serve it
  headlessly and open it with the browser/computer-use tool:
  `flutter run -d web-server --web-port=8080 --web-hostname=0.0.0.0`, then browse
  to `http://localhost:8080`. The first web compile takes ~15–20s before the app
  appears — wait for it rather than assuming a blank screen is a failure.
- **Backend config is not committed.** Supabase URL/key are read at runtime from
  a gitignored `.env` file (loaded by `flutter_dotenv`). Copy `.env.example` to
  `.env` and fill in `SUPABASE_URL` / `SUPABASE_ANON_KEY` from the Supabase
  dashboard. The startup update script generates `.env` automatically: if the
  `SUPABASE_URL` / `SUPABASE_ANON_KEY` **environment variables** are set (e.g.
  added as Cursor secrets) it writes them into `.env`; otherwise it copies
  `.env.example`. So builds never fail on the missing asset — but with blank
  values the app boots, Settings shows "Not configured", and the Destinations
  tab shows a friendly "cannot reach" message. This is expected until real keys
  are added. To connect for real in a cloud run, add `SUPABASE_URL` and
  `SUPABASE_ANON_KEY` as secrets.
- `.env` is declared as a Flutter **asset** in `pubspec.yaml`; it must exist for
  `flutter run`/`build` to succeed (hence the auto-copy above).
- **Database schema + demo seed** live in `supabase/` (`migrations/0001_exploreros_schema.sql`,
  `seed.sql`). Apply them in the Supabase SQL editor / CLI so the app has live
  content. Table columns are the snake_case contract for the Dart models'
  `fromJson`/`toJson` — keep them in sync when changing a model.
- **Client key MUST be the publishable key.** Supabase rejects `sb_secret_…`
  keys from browser clients with HTTP 401 `"Forbidden use of secret API key in
  browser"` (server-side `curl` still works, which is misleading). Flutter web is
  a browser client, so `SUPABASE_ANON_KEY` must be the `sb_publishable_…` (anon)
  key from Project Settings → API. A secret key will 401 every query even though
  the URL/schema are correct.
- **The live project uses Base44's schema, not the app's original tables.** The
  connected Supabase project is managed by Base44 Admin: content lives in
  `destinations`, `media` (audio/photo/video; audio `file_url` resolves against
  the public **`mp3`** Storage bucket), `stops`, and `stories`. The app's older
  `songs` / `radio_stations` / `music_*` tables do NOT exist there. Mapping is
  handled in `Destination.fromJson` (Base44 columns: `destination_id`,
  `hero_image`, `destination_type`, `state_province`/`country`) and in
  `features/media/` (`MediaRepository.songsForDestination` maps audio `media`
  rows to `Song`s; `RadioStation.fromDestination` derives a station per
  destination). Radio playlists come from a destination's audio `media`, not a
  `radio_stations` table.
- **Google Maps (Map tab).** The web build loads the Maps JavaScript API via a
  `<script>` in `web/index.html` with the placeholder `__GOOGLE_MAPS_API_KEY__`
  (the raw key is never committed). Inject the real key into the **built**
  `build/web/index.html` (e.g. `sed -i "s/__GOOGLE_MAPS_API_KEY__/$GOOGLE_MAPS_API_KEY/" build/web/index.html`)
  after `flutter build web`, before serving. It's a client-side key by design —
  restrict it by HTTP referrer and enable "Maps JavaScript API" in Google Cloud
  Console. The Map plots destinations with coordinates (`latitude`/`longitude`).
- **Gotcha: after adding a web plugin, `flutter clean` before building.** Flutter
  can reuse a cached `web_plugin_registrant.dart` that omits a newly added web
  plugin. Symptom: `google_maps_flutter` throws `"TargetPlatform.linux is not
  yet supported by the maps plugin"` on web even though the key/schema are fine.
  Fix: `flutter clean && flutter pub get && flutter build web` so the registrant
  regenerates with `GoogleMapsPlugin.registerWith`.
- **Map clustering needs the markerclusterer script.** `google_maps_flutter_web`'s
  `ClusterManager` binds to the global `markerClusterer`, loaded by the
  `@googlemaps/markerclusterer` `<script>` in `web/index.html`. If that script is
  removed, the whole web map fails to initialize (`Cannot read properties of
  undefined (reading 'MarkerClusterer')`) whenever a `ClusterManager` is present.
- **Server-side AI tools read keys from the environment, not `.env`.** The
  content pipeline scripts in `tool/` (`research_destination.dart`,
  `story_generate.dart`, `story_audio.dart`, `dj_audio.dart`,
  `narration_audio.dart`) read `OPENAI_API_KEY` / `ELEVENLABS_API_KEY` and
  `SUPABASE_SERVICE_KEY` (falls back to `SUPABASE_ANON_KEY`) from environment
  variables (Cursor secrets), so they need those secrets set — the Flutter app's
  `.env` is not used by them. Run e.g.
  `dart run tool/research_destination.dart --destination "Rainbow Springs State Park" --category state_park --state Florida`
  (add `--dry-run` to validate wiring without calling OpenAI).
- **Central audio engine: `lib/features/playback/`.** `PlaybackManager`
  (`playback_manager.dart`) is the single source of truth for all music +
  narration playback; other systems (GPS, Explorer Radio, narration, POIs)
  should route audio through it, never touch `just_audio` directly. It runs two
  `AudioOutput` channels (music + narration) so music is ducked/faded and resumed
  around narration, and it uses a priority queue (emergency 100 → music 10).
  State transitions are **optimistic**: state/events update synchronously and the
  actual source load runs in the background (load failures surface via the
  `errorOccurred` event), so never rely on `play()` resolving before the state
  flips. Riverpod entry points are in `playback_providers.dart`; unit tests use a
  fake `AudioOutput` (`test/playback_manager_test.dart`). The admin **Playback
  Debug** module (Platform group) exercises the engine end-to-end in a browser.
- **Narration "Generate" buttons only enqueue `generation_jobs`** — they do not
  create scripts/audio directly (the AI keys are server-side only). A worker must
  drain the queue: the **`.github/workflows/narration-worker.yml`** GitHub Action
  (runs every 15 min + on demand via `run.ts`), or the `tool/*.dart` /
  `tool/*.py` CLIs run manually. If admins report "the queue isn't running
  automatically," check **Actions → Narration Worker** run logs.
- **The queue worker depends on THREE GitHub Actions repo secrets.** The workflow
  aborts in seconds (and nothing drains) unless these exist under GitHub →
  Settings → Secrets and variables → **Actions**: `SUPABASE_SERVICE_KEY`,
  `OPENAI_API_KEY`, `ELEVENLABS_API_KEY` (optional `SUPABASE_URL`, else defaults
  to the project URL). These are **separate** from the app `.env` and from Cursor
  secrets — setting Cursor secrets does NOT populate GitHub Actions secrets. The
  worker (`supabase/functions/narration-worker/worker.ts`) drains: `research`,
  `narration`, `narration_audio`, `full`, plus `wikimedia_import` (Commons hero
  images → `media` bucket + `locations.images` + `media_assets`) and `audio` jobs
  whose `notes` start with `master_location` (OpenAI+ElevenLabs narration →
  `voiceovers` bucket + `locations.audio_files`). Other `audio:*` variants
  (species records, `dj_banter`, batch) are intentionally left for their own
  tooling. It self-heals `running` rows back to `pending` at the start of each
  run (safe because the workflow's concurrency group serializes runs).
