# Database Map — Base44 / Supabase (`qqeyvhcgirmfokoftiuz`)

Field-level map of every table in the live project. Types are the PostgREST/
Postgres types from the OpenAPI schema. `PK` = primary key, `FK →` = foreign key.

## `destinations` — Parks / Destinations
PK: `destination_id` (uuid)

| Field | Type | Notes |
|---|---|---|
| destination_id | uuid | **PK**, required |
| destination_code | text | required (e.g. YELL) |
| name | text | required |
| slug | text | required |
| destination_type | text | required (National Park, etc.) |
| country | text | required |
| state_province | text | |
| managing_agency | text | |
| latitude / longitude | numeric | GPS |
| timezone | text | IANA |
| address / phone / website | text | |
| description | text | |
| hero_image / logo / cover_video | text | media URLs |
| featured / published / offline_supported | boolean | |
| created_at / updated_at | timestamptz | |

## `stops` — Locations (POIs)
PK: `stop_id` · FK: `destination_id → destinations`

| Field | Type | Notes |
|---|---|---|
| stop_id | uuid | **PK**, required |
| destination_id | uuid | **FK → destinations.destination_id**, required |
| stop_name | text | required |
| stop_type | text | required |
| short_description / full_description | text | |
| latitude / longitude | numeric | required (GPS) |
| elevation_ft | integer | |
| address | text | |
| gps_trigger_radius_meters | integer | geofence radius |
| estimated_visit_minutes | integer | |
| parking_available / restroom_available / accessible | boolean | |
| featured / published | boolean | |
| sort_order | integer | |
| hero_image | text | |
| audio_available | boolean | |
| created_at / updated_at | timestamptz | |

## `stories` — Stories / Narrations
PK: `story_id` · FK: `destination_id → destinations`, `stop_id → stops`, `hero_media_id → media`

| Field | Type | Notes |
|---|---|---|
| story_id | uuid | **PK**, required |
| destination_id | uuid | **FK → destinations**, required |
| stop_id | uuid | FK → stops |
| title | text | required |
| story_category | text | required |
| audience_type / difficulty_level | text | |
| short_summary / full_story / ai_summary | text | |
| voice_script | text | narration script |
| estimated_read_minutes / estimated_audio_seconds | integer | |
| gps_trigger_radius_meters | integer | |
| trigger_latitude / trigger_longitude | numeric | GPS trigger |
| narrator_voice | text | |
| hero_media_id | uuid | FK → media.media_id |
| featured / published | boolean | |
| sort_order | integer | |
| created_at / updated_at | timestamptz | |

## `knowledge_articles` — AI Ranger knowledge
PK: `knowledge_id` · FK: `destination_id → destinations`, `stop_id → stops`, `hero_media_id → media`

| Field | Type | Notes |
|---|---|---|
| knowledge_id | uuid | **PK**, required |
| destination_id | uuid | **FK → destinations**, required |
| stop_id | uuid | FK → stops |
| title | text | required |
| category | text | required |
| summary | text | |
| content | text | required |
| voice_script / ai_summary | text | |
| hero_media_id | uuid | FK → media |
| reading_time_minutes / audio_length_seconds | integer | |
| featured / published | boolean | |
| sort_order | integer | |
| created_at / updated_at | timestamptz | |

## `media` — Photos / Videos / Audio
PK: `media_id` · FK: `destination_id → destinations`, `stop_id → stops`

| Field | Type | Notes |
|---|---|---|
| media_id | uuid | **PK**, required |
| destination_id | uuid | **FK → destinations**, required |
| stop_id | uuid | FK → stops |
| media_type | text | required (audio/photo/video) |
| title / description | text | |
| file_name | text | |
| file_url | text | required (→ `mp3` bucket for audio) |
| thumbnail_url | text | |
| photographer / copyright_holder / license | text | |
| latitude / longitude | numeric | |
| taken_date | date | |
| is_featured | boolean | |
| sort_order | integer | |
| tags | text[] | |
| alt_text | text | |
| published | boolean | |
| created_at / updated_at | timestamptz | |

## Non-content tables
- **`radio`** — data dictionary: `table, field_name, data_type, required, description` (24 rows describing `destinations`). Not radio content.
- **`narrations`** — a single warning row; schema-context only, not usable.
- **`visitor`** — `visitor` (bigint PK), `created_at`.
- **`visitor_csv_data`** — `id` (uuid PK), `user_id`, `filename`, `row_index`, `data` (jsonb), `uploaded_at`. A CSV import artifact.

## Entity relationship (content)
```
destinations (destination_id)
  ├─< stops (destination_id)
  │     └─< media (stop_id) ┐
  ├─< media (destination_id) ┤ audio → mp3 bucket
  ├─< stories (destination_id, stop_id, hero_media_id → media)
  └─< knowledge_articles (destination_id, stop_id, hero_media_id → media)
```
