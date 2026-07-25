# Base44 Data Inventory

Discovered by live inspection of the Supabase project **`qqeyvhcgirmfokoftiuz`**
(the backend Base44 Admin uses): PostgREST OpenAPI schema, row counts, Storage
buckets, and Auth settings. Nothing invented; empty/absent items are labeled.

## Access status
- **Base44 ↔ Supabase:** the project holds Base44's schema + a `radio`
  data-dictionary + a `visitor_csv_data` import, so Base44 provisioned/uses this
  project. **Content tables are currently empty** (no park content authored yet).
- **Reachable API:** Supabase REST/PostgREST + Storage. The **publishable key**
  reads all content tables (RLS allows anon SELECT); the **secret key** is used
  only server-side for this analysis.

## Tables discovered

| Table | Rows | Role |
|---|---|---|
| `destinations` | 0 | **Parks/Destinations** (top-level content) |
| `stops` | 0 | **Locations** (POIs within a destination) |
| `stories` | 0 | **Stories** (narration/scripts + GPS triggers) |
| `knowledge_articles` | 0 | **AI Ranger knowledge** (articles + voice scripts) |
| `media` | 0 | **Media** (photo/video/audio; audio → `mp3` bucket) |
| `narrations` | 0 | placeholder (schema-context only, not usable) |
| `radio` | 24 | **data dictionary** (documents the `destinations` schema; not content) |
| `visitor` | 0 | trivial (`visitor` bigint, `created_at`) |
| `visitor_csv_data` | 182 | CSV import artifact (`data` jsonb) — not domain content |

## Storage buckets

| Bucket | Public | Notes |
|---|---|---|
| `mp3` | yes | the only bucket; audio (`media.file_url`) |

No `photos`, `videos`, `documents`, `artwork`, `logos`, or `gpx` buckets exist.

## Relationships / foreign keys
- `stops.destination_id → destinations.destination_id`
- `media.destination_id → destinations.destination_id`, `media.stop_id → stops.stop_id`
- `stories.destination_id → destinations`, `stories.stop_id → stops`, `stories.hero_media_id → media.media_id`
- `knowledge_articles.destination_id → destinations`, `.stop_id → stops`, `.hero_media_id → media`

## Media / images / videos / audio
- All handled by the single **`media`** table via `media_type` + `file_url`
  (+ `thumbnail_url`). Audio files live in the public **`mp3`** bucket.
- `destinations.hero_image / logo / cover_video` and `stops.hero_image` are
  direct URL columns.

## GPS coordinates
- `destinations.latitude/longitude`, `stops.latitude/longitude`,
  `media.latitude/longitude`, `stories.trigger_latitude/longitude`
  (+ `gps_trigger_radius_meters` on `stops` and `stories`).

## Entities requested but NOT present (no table/bucket)
Parks*, Wildlife, Plants, Birds, Trails, Routes, Historical Events, Radio
Stations, Songs, Albums, Users/Profiles, Subscriptions, Analytics.

\*"Parks" is represented by **`destinations`** (there is no separate `parks`
table). The rest have **no backing data** in Base44 yet.

## Users / auth
- Supabase Auth: **email provider enabled**, anonymous disabled, no OAuth.
- **No users, no `profiles`/roles table.** No admin identity model.

## Analytics
- **None.** No analytics tables/events.

See `DATABASE_MAP.md` for full field-level detail and `FLUTTER_DATA_GAP_REPORT.md`
for the comparison against the Flutter app.
