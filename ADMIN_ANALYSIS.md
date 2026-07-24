# ExplorerOS Admin — Analysis (pre-implementation)

This document analyzes the **existing** admin/content situation before building
anything, per the redesign brief. The goal is to avoid duplicating pages,
tables, components, or services, and to reuse what already exists.

> TL;DR: There is **no admin portal in this repository**. Content is authored
> today in the **external Base44 Admin** (a no-code platform) over Supabase.
> This repo is the **read-only Flutter mobile client** plus a large set of
> reusable models/repositories/services. The redesigned admin is therefore a
> **new in-repo Flutter-web app** that reuses those layers and the same Supabase
> project — not a rewrite of anything already here.

---

## 1. Existing pages

### 1a. In-repo (mobile app screens — NOT admin pages)
| Screen | File | Purpose |
|---|---|---|
| `HomeScreen` | `lib/features/home/presentation/home_screen.dart` | Dashboard of nav cards |
| `DestinationsScreen` | `lib/features/destinations/presentation/destinations_screen.dart` | Explore list + search/filter |
| `DestinationDetailsScreen` | `.../destination_details_screen.dart` | Single destination detail |
| `MapsScreen` | `lib/features/maps/presentation/maps_screen.dart` | Google Map of destinations |
| `RadioScreen` | `lib/features/radio/presentation/radio_screen.dart` | Explorer Radio player |
| `AiRangerScreen` | `lib/features/companion/presentation/ai_ranger_screen.dart` | Placeholder |
| `StoriesScreen`, `WildlifeScreen`, `GpsScreen`, `DownloadsScreen` | `lib/features/*/presentation/` | Placeholders |
| `MoreScreen`, `ProfileScreen`, `SettingsScreen` | `lib/features/*/presentation/` | Menus / settings |

These are **consumer** screens (mobile), not content-management pages.

### 1b. Admin pages (external)
The current admin is **Base44 Admin** — a hosted no-code tool with **no source
code in this repo**. It cannot be edited/extended from here. Its schema is
mirrored into Supabase (see §2).

**Conclusion:** No admin pages exist to reuse or duplicate. The new admin is
green-field UI, but it will reuse this repo's data layer (§3–§4).

---

## 2. Existing database tables

There are **two different table sets** and they do **not** match — a critical
finding for the admin.

### 2a. Tables that actually exist in the live Supabase project
(Verified by querying `https://qqeyvhcgirmfokoftiuz.supabase.co` via the REST
OpenAPI + PostgREST.)

| Table | Rows (at analysis time) | Notes |
|---|---|---|
| `destinations` | 0 | Full Base44 schema (`destination_id`, `hero_image`, `destination_type`, `state_province`, `latitude/longitude`, `featured`, `published`, …) |
| `media` | 0 | audio/photo/video: `media_id`, `media_type`, `file_url`, `destination_id`, `stop_id`, `is_featured`, `published` |
| `stops` | 0 | POIs: `stop_id`, `destination_id`, lat/lng, `audio_available`, trigger radius |
| `stories` | 0 | `story_id`, `destination_id`, `voice_script`, `estimated_audio_seconds`, GPS trigger fields, `hero_media_id` |
| `knowledge_articles` | 0 | `voice_script`, `audio_length_seconds` (AI Ranger knowledge) |
| `narrations` | 0 | placeholder/context table |
| `radio` | 24 | **data dictionary** (columns: `table, field_name, data_type, required, description`) — not radio content |
| `visitor` | 0 | trivial |
| `visitor_csv_data` | 182 | imported CSV rows (only table with data) |

**Storage buckets:** a single public **`mp3`** bucket (empty at analysis time).

### 2b. Tables the mobile app expects but that DO NOT exist live
The Flutter app declares 31 table constants in
`lib/core/data/supabase_tables.dart`, but most are **not provisioned** in the
live project: `parks`, `wildlife`, `plants`, `songs`, `radio_stations`,
`announcements`, `station_rules`, `station_profiles`, `gps_audio_triggers`,
`playback_history`, `park_boundaries`, `state_boundaries`, `county_boundaries`,
`location_history`, `travel_sessions`, `albums`, `genres`, `moods`, `artworks`,
`music_metadata`, `playlists`, `station_assignments`, `gps_music_triggers`,
`upload_jobs`, `user_favorites`, `downloads`.

Repo migrations under `supabase/migrations/` (`0001_exploreros_schema.sql`,
`0002_music_library.sql`) define a *different* schema than Base44 created.

**Implication for the admin:** the admin must target the **live Base44 schema**
(`destinations`, `media`, `stops`, `stories`, `knowledge_articles`) as the
source of truth, and treat the app's extra tables as a **roadmap** to be created
by migration when those modules are built. Normalizing on Base44's schema avoids
duplicate tables.

---

## 3. Existing media management

- **Table:** `media` (audio/photo/video) with `file_url` pointing into the
  public **`mp3`** Storage bucket. Model: `lib/features/media/models/media_item.dart`.
- **Read repo:** `MediaRepository` (`lib/features/media/data/media_repository.dart`)
  — filters audio, resolves bucket URLs, maps to `Song`.
- **Music library (write seams already built):**
  - `MusicStorageService` — uploads audio/artwork bytes to Supabase Storage.
  - `MusicWriter` / `SupabaseMusicWriter` — bulk write to `songs`/`albums`/`music_metadata`.
  - `BulkImportService`, `CSVImporter`, `ZIPImporter` — bulk ingest.
  - `ArtworkService`, `MetadataService`, `MusicLibraryService`.
- **Gap:** no UI to browse/upload/tag media; no folders/tags/compression; the
  music write paths target the not-yet-created `songs`/`albums` tables.

**Reuse:** `MediaRepository`, `MusicStorageService`, `MusicWriter`, importers.

---

## 4. Existing user management

- **None.** No auth, no roles, no `users`/`profiles` table live. `visitor` /
  `visitor_csv_data` are unrelated to admin identity.
- Supabase Auth is available but not wired. `SupabaseService` initializes the
  client only; there is no sign-in flow.
- RLS in repo migrations is "demo-open" with TODOs to tighten to `auth.uid()`.

**Gap:** authentication, an admin `profiles`/roles table, and the 5 requested
roles (Administrator, Editor, Content Creator, Guide, Read Only) must be built.

---

## 5. Existing APIs

- **Supabase auto-generated REST** (PostgREST) over every table —
  `GET/POST/PATCH/DELETE /rest/v1/<table>`. This is the primary API.
- **Supabase Storage API** — `/storage/v1/object/...` (the `mp3` bucket).
- **Supabase Realtime / Auth / Edge Functions** — available, not yet used.
- No custom backend/API server exists. `SupabaseService.client`
  (`lib/core/services/supabase_service.dart`) is the single doorway; the generic
  `SupabaseReadRepository` / `SupabaseSyncRepository`
  (`lib/core/data/read_repository.dart`) provide list/get/upsert/delete.

**Reuse:** the generic repositories give the admin CRUD for free per table.

---

## 6. Existing integrations

| Integration | Where | Status |
|---|---|---|
| Supabase (DB + Storage) | `supabase_flutter`, `SupabaseService` | Active |
| Base44 Admin | external | Source of live schema/content |
| Google Maps | `google_maps_flutter` + `web/index.html` key | Active (Map tab) |
| `just_audio` / `audio_service` | radio playback + background | Active |
| `geolocator` | GPS engine | Active |
| `flutter_dotenv` | `.env` config | Active |

**Key gotcha (documented in AGENTS.md):** browser clients must use the
`sb_publishable_` key — Supabase 401s `sb_secret_` keys from browsers. The
Flutter-web admin is a browser client, so it needs the publishable key.

---

## 7. Missing functionality (the admin scope)

Essentially the entire CMS is missing. Grouped against the brief:

- **Shell/UX:** admin layout, sidebar, top bar, global search, notifications,
  quick actions, profile menu, dark/light mode, breadcrumbs, responsive grid.
- **Dashboard:** KPI widgets, recent activity, storage usage, publish queue.
- **Content modules:** Parks, Locations, Trails, Routes, Stories, Explorer Radio,
  Music Library, Albums, Wildlife, Plants, Birds, Historical Events, Media
  Library, AI Content, Downloads.
- **Visual Map Editor:** click-to-create locations, drag markers, trigger radius,
  boundaries/trails overlays, satellite/terrain, save.
- **Platform:** Users + roles/permissions, Subscriptions, Analytics, Settings.
- **Data gaps:** tables for parks, trails, routes, wildlife, plants, birds,
  historical events, albums/songs, users/roles, subscriptions, analytics.
- **Non-functional:** pagination, lazy loading, image optimization, bulk actions,
  autosave, caching, drag-and-drop uploads.

---

## 8. Reuse map (what the admin will build on)

| Admin need | Reuse from repo |
|---|---|
| Backend access | `SupabaseService`, `supabaseClientProvider` |
| CRUD per table | `SupabaseReadRepository` / `SupabaseSyncRepository` |
| Parks/Locations | `Destination`/`Stop` models, `DestinationRepository`, `destinationsProvider` |
| Media | `MediaItem`, `MediaRepository`, `MusicStorageService` |
| Stories | `Story`, `StoryRepository` |
| Music | `Album/Song/MusicMetadata/...`, `MusicRepository`, `BulkImportService` |
| Wildlife/Plants | `Wildlife`/`Plant` models + repos |
| Radio | `RadioStation`, `Announcement`, `StationProfile`, `RadioRepository` |
| Map editor | `google_maps_flutter` (already integrated) |
| Design tokens | `AppColors/AppTypography/AppSpacing/AppRadius/AppShadows` |
| Shared UI | `AppCard`, `PrimaryButton`, `SectionHeader`, `LoadingWidget`, `ErrorView` |

**Decision:** build the admin as a **Flutter-web target in this repo**
(`lib/main_admin.dart` + `lib/features/admin/`) so it reuses every layer above
and stays consistent with the ExplorerOS architecture. See
`ADMIN_ARCHITECTURE.md`.
