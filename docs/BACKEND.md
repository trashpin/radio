# ExplorerOS Backend (Supabase)

GPS-powered destination discovery + AI radio platform. This document describes the
Supabase (PostgreSQL) backend: schema, pipelines, security, functions, views, and
how to run the migrations. It is designed to scale from Florida State Parks to
nationwide coverage without a redesign.

## How the schema is delivered

The backend grew across numbered SQL migrations in `supabase/migrations/`. They are
**additive and idempotent** — safe to run in order and safe to re-run. Run each new
one in the Supabase SQL editor (project `qqeyvhcgirmfokoftiuz`).

| Migration | Adds |
|---|---|
| `0014_import_content_tables.sql` | `map_locations`, `trails`, `campgrounds`, `historical_events` |
| `0015_dj_banter_clips.sql` | `dj_banter_clips` |
| `0016_radio_automation.sql` | `radio_segments`, `radio_schedule_rules` |
| `0017_story_library.sql` | `story_library` (AI stories + GPS + audio) |
| `0018_content_generator.sql` | `knowledge_base`, `generation_jobs` |
| **`0019_backend_foundation.sql`** | **Auth/roles, user tables, ops tables, content-support tables, cross-cutting triggers, FTS + GPS indexes, helper functions, dashboard views, Storage buckets** |
| **`0020_master_destinations.sql`** | **Master Destination System: new destination columns, auto `destination_code`/`slug`/`id`, `gps_zones`, `destination_id` FKs on content tables, counts/status, dashboard view, indexes, RLS** |
| **`0021_destination_write_access.sql`** | **Write RLS on `destinations` (insert/update/delete) so the admin dashboard + CSV importer can create/import/edit destinations** |
| **`0022_narration_studio.sql`** | **AI Narration Studio: `destination_narrations` (25 script types + variants + QC) and `route_narrations`, coverage view, `random_narration()`, indexes, RLS** |

Earlier migrations (`0001`–`0013`) established the original content tables
(`destinations`, `species`, `media`, `songs`, `stories`, …).

## `0019_backend_foundation.sql` at a glance

This migration fills the gaps needed for a production platform. It never drops or
rewrites existing tables; every table-dependent object is guarded so a missing
table is skipped rather than aborting the run.

### Auth & roles
- `profiles` — one row per `auth.users` row (auto-created by the
  `on_auth_user_created` trigger). Column `role` is `user` | `editor` | `admin`.
- `is_admin()` — `true` when the current user's profile role is `admin`. Used by
  RLS on sensitive ops tables.
- **Promote an admin:** `update public.profiles set role='admin' where id='<auth-uid>';`

### User-facing tables (owner-scoped RLS)
`bookmarks`, `favorites`, `trips`, `trip_stops`, `user_progress`, `achievements`,
`user_achievements`, `notifications`. Each user reads/writes only their own rows
(`user_id = auth.uid()`).

### Content-support tables (public read, open write)
`businesses`, `events`, `images`, `videos`, `voice_profiles`, `story_versions`,
`story_reviews`, `story_tags`, `knowledge_sources`. RLS matches the app's existing
pattern (anyone can read, authenticated/anon can write). Tighten writes to
`is_admin()` once the admin role model is fully adopted.

### Ops / platform tables (admin-only RLS)
`audit_logs`, `system_logs`, `feature_flags`, `api_keys`, `analytics_events`,
`import_jobs`, `export_jobs`. Reads are gated to admins; writes flow through
`SECURITY DEFINER` triggers/functions or the service role.

## Master Destination System (`0020`)

`destinations` is the central source of truth for every destination type (state
parks, national parks/forests, springs, WMAs, scenic drives, historic sites,
museums, cities, beaches, campgrounds, trailheads, businesses) and scales to all
50 states. The migration is additive — every existing column and row is
preserved.

- **New columns:** `county`, `city`, `region`, `subcategory`, `gps_radius_ft`,
  `email`/`facebook`/`instagram`/`youtube`, `ai_enabled`, per-stage status
  (`research_status`, `story_status`, `audio_status`, `image_status`,
  `video_status`), counts (`story_count`, `audio_count`, `image_count`,
  `play_count`), `priority`, `visitor_center`, `pet_friendly`, `accessibility`,
  `best_season`, `entrance_fee`, `reservation_required`, `last_ai_research` /
  `last_story_generation` / `last_audio_generation`, and `metadata` (JSONB).
- **Scalable codes:** `trg_destination_defaults` (BEFORE INSERT) fills
  `destination_id`, `slug`, and a `destination_code` like `FLNF0001`,
  `FLSP0001`, `FLSPR0001`, `FLCITY0001`, `UTNP0001` via
  `generate_destination_code(type, state)` (uses `state_abbrev` +
  `destination_type_prefix`). Existing codes such as `OCALA` are preserved.
- **Normalization:** a new `gps_zones` table (arrival/departure/approach/scenic/
  trail/road triggers) and a `destination_id` foreign key added to every content
  table (`stories`, `story_library`, `knowledge_base`, `species`, `trails`,
  `campgrounds`, `events`, `businesses`, `images`, `videos`, `media`,
  `generation_jobs`, …). `media` + `narrations` remain the audio store.
- **Counts/status:** `recalc_destination_counts(uuid)` and
  `recalc_all_destination_counts()` refresh the cached counts;
  `v_destination_dashboard` exposes status + counts for the admin.
- **Admin UI:** the **Destinations** module (`destination_dashboard_page.dart`)
  lists destinations with AI-status chips, counts, and filters (type, county,
  region, published, research/audio status), toggles publish, and launches AI
  jobs per destination (enqueues `generation_jobs`). Bulk import uses the
  **Destinations** CSV target; the DB trigger generates code/slug/id.
- **Bulk import (direct passthrough):** the **Destinations** CSV target maps every
  column straight to the `destinations` table by header name (e.g. `Destination
  Type` → `destination_type`), performs no value validation (values like `USA`
  and `State Park` pass through), pre-blocks nothing, and shows Supabase errors
  per row. It requires `0020` (auto id/slug/code) and `0021` (write access) to
  import successfully; without them the DB returns `NOT NULL` / `42501 RLS`
  errors, which the importer surfaces per row.

## AI Narration Studio (`0022`)

Per-destination, multi-script AI narration + destination-to-destination route
narration, grounded only in ExplorerOS knowledge.

- **Tables:** `destination_narrations` (25 script types — arrival, main/extended
  history, wildlife, plants, trees, birds, geology, fun facts, family/kids,
  accessibility, scenic, hidden gems, departure, night/sunrise/sunset, rainy day,
  emergency, … — with `variant`, `language`, `season`, `time_of_day`, an
  approval→publish `status`, and QC columns: `word_count`, `speaking_seconds`
  @150 wpm, `readability_score`, `fact_confidence`, `duplicate_score`,
  `needs_review`) and `route_narrations` (from/to destination, distance, drive
  time, script/audio).
- **View/function:** `v_destination_narration_coverage` (scripts/audio/approved/
  published/needs_review per destination) and `random_narration(dest, type,
  lang)` so Explorer Radio rotates published variants.
- **Admin UI:** the per-destination **Narration Studio** (opened from the
  Destinations dashboard → ⋮ → Narration Studio): coverage header, all 25 script
  types with variants + QC + lifecycle actions (Approve/Publish/Edit/Generate
  Audio/…), and Generate All / Generate Missing. QC helpers live in
  `lib/features/narration/narration_qc.dart` (pure + unit-tested).
- **Generation:** `dart run tool/generate_narration.dart --destination "Ocala
  National Forest" [--types arrival,fun_facts] [--mode all|missing]
  [--max-variations N] [--dry-run]`. Writes ranger-style scripts grounded ONLY
  in `knowledge_base` + `species` for the destination (never invents facts; emits
  a `needs_review` placeholder when a destination has no knowledge). With no
  `--destination` it drains pending `generation_jobs` where `job_type='narration'`.
  Requires `OPENAI_API_KEY` + `SUPABASE_SERVICE_KEY`.

## Story pipeline

```
Research → Knowledge Base → Story Generation → Review → Approval
       → Audio Generation → GPS Assignment → Publishing
```

- Research + facts land in `knowledge_base` (with `knowledge_sources`).
- Drafts land in `story_library` (`status`, `approved`, `published`).
- **Trigger `trg_queue_audio`**: when a story flips to `approved` and has no
  `audio_url`, an `audio` job is auto-inserted into `generation_jobs`.
- `publish_story(uuid)` approves + publishes in one call.
- Audio is stored permanently and reused (never regenerate unchanged audio).

## Radio system

`radio_segments` (station IDs, DJ banter, history/wildlife/safety/ads/promotions),
`radio_schedule_rules` (16 trigger types), `dj_banter_clips`, `songs`. The radio
engine assembles dynamic playlists from pre-generated content and interrupts music
on GPS arrival.

## GPS system

Destinations and stories carry `latitude`, `longitude`, and a trigger radius
(`trigger_radius_m`), plus priority/direction metadata. `nearby_destinations(lat,
lng, radius_km)` returns published destinations nearest-first;
`gc_meters(...)` is the great-circle distance helper.

## AI content pipeline (background jobs)

`generation_jobs` supports research, story writing, audio, image, translation, and
summary jobs with statuses `pending` → `running` → `completed` / `failed`, plus
retry/cancel and messages. Server tools in `tool/` (`research_destination.dart`,
`story_generate.dart`, `story_audio.dart`, `dj_audio.dart`) process the queue via
OpenAI + ElevenLabs.

## Search

Full-text search via generated `search_tsv` columns + GIN indexes on
`destinations`, `story_library`, `knowledge_base`, and `species`. Example:

```sql
select name from destinations where search_tsv @@ to_tsquery('english', 'spring');
```

## Performance / indexes

GPS lookups (`(latitude, longitude)` on destinations / story_library /
map_locations), story retrieval (`(published, category)`), FTS GIN indexes, and
per-user indexes on bookmarks/favorites/progress/notifications. Designed for
hundreds of thousands of destinations and millions of records.

## Functions

| Function | Purpose |
|---|---|
| `is_admin()` | Current user is an admin |
| `gc_meters(lat1,lng1,lat2,lng2)` | Great-circle distance (meters) |
| `nearby_destinations(lat,lng,radius_km)` | Published destinations, nearest first |
| `random_published_story(park)` | Random audio-ready published story |
| `publish_story(uuid)` | Approve + publish a story |
| `content_statistics()` | Counts (destinations/stories/jobs/…) as JSON |
| `db_health()` | Table count + DB size snapshot |

## Views

`v_published_stories`, `v_missing_audio`, `v_gps_ready_stories`,
`v_jobs_dashboard`, `v_content_statistics`.

## Triggers

- `trg_set_updated_at` — maintains `updated_at` on every base table that has the column.
- `trg_queue_audio` — queues audio generation when a story is approved.
- `on_auth_user_created` — creates a `profiles` row for each new auth user.

## Storage buckets

`audio`, `images`, `videos`, `documents`, `avatars`, `uploads` (public);
`exports`, `temporary` (private). Created idempotently from the migration.

## Row Level Security summary

| Audience | Access |
|---|---|
| Anonymous | Read published content |
| Authenticated | Own bookmarks / favorites / trips / progress; read content |
| Admin (`profiles.role='admin'`) | Full access to ops tables + everything |

## Validating migrations locally

The SQL is validated against a local Postgres 16 with Supabase stubs (`auth`,
`storage`, `anon`/`authenticated` roles). To reproduce: start a local cluster,
create the stub `auth`/`storage` objects, run `0014`→`0019`, then run `0019` again
to confirm idempotency.
