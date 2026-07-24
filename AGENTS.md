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
