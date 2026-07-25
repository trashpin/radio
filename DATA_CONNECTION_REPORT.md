# Data Connection Report

Final report for connecting the ExplorerOS Flutter app to the existing Base44
data in Supabase project **`qqeyvhcgirmfokoftiuz`**. See also
`BASE44_DATA_INVENTORY.md`, `DATABASE_MAP.md`, `FLUTTER_DATA_GAP_REPORT.md`.

## Is Base44 connected to Supabase / is there an accessible API?
**Yes.** The project exposes Supabase REST (PostgREST) + Storage. The
**publishable key** reads all content tables from a browser (RLS allows anon
SELECT), verified below. Base44's schema (destinations/stops/stories/
knowledge_articles/media + a `radio` data-dictionary + a `visitor_csv_data`
import) is present, so integration could proceed. **Content is currently empty**
(no park content authored in Base44 yet).

## Data discovered
- **Content tables:** `destinations` (Parks), `stops` (Locations), `stories`,
  `knowledge_articles` (AI Ranger), `media` (photo/video/audio).
- **Storage:** one public bucket `mp3` (audio).
- **Relationships/FKs:** all content FK to `destinations`; `media`/`stories`/
  `knowledge_articles` reference `stops` and `media` (`hero_media_id`).
- **Not present (no table/bucket):** parks (separate), wildlife, plants, birds,
  trails, routes, radio_stations, songs, albums, users/profiles, subscriptions,
  analytics, and photo/video/document/artwork/logo/gpx buckets.

## Connected successfully
Reused existing structures; **no duplicate tables/models/repositories** created.

| Module | Source table | Flutter binding | Live read (publishable key) |
|---|---|---|---|
| Dashboard / Parks | `destinations` | `Destination` + `DestinationRepository` (aligned) | **200** |
| Locations | `stops` | `Stop` (**re-aligned**) + `StopRepository.byDestination` | **200** |
| Stories | `stories` | `Story` (**re-aligned**) + `StoryRepository.byDestination` | **200** |
| AI Ranger knowledge | `knowledge_articles` | `KnowledgeArticle` (**new**) + `KnowledgeArticleRepository` | **200** |
| Media Library | `media` | `MediaItem` + `MediaRepository` | **200** |
| Media storage | `mp3` bucket | `MediaRepository.resolveUrl` | **200** |

Changes made in Step 4:
- Re-aligned `Stop` and `Story` `fromJson` to Base44 columns (kept the classes;
  added legacy fallbacks). Repointed stop/story relationship queries from
  `park_id` → `destination_id`; added `…ByDestination` providers (old
  `…ByParkProvider` names kept as aliases).
- Added the missing `KnowledgeArticle` model + `KnowledgeArticleRepository` +
  `knowledgeArticles` table constant + `knowledgeArticlesByDestinationProvider`.
- Verified all mappings with unit tests (`test/base44_mapping_test.dart`,
  `test/base44_media_test.dart` — 10/10 pass) using Base44-shaped JSON, and
  verified live reachability per module with the publishable key.

## Missing connections (no backing data yet)
These modules have Flutter models/repos but **no Base44 table** — they return
`404` and stay as roadmap until their tables exist:
- **Music Library / Albums / Songs / Radio Stations** → `songs`, `albums`,
  `radio_stations` (404). Audio is available today via `media` instead.
- **Wildlife / Plants / Birds / Trails / Routes** → `wildlife`, `plants`,
  `trails`, … (404).
- **Users / Analytics / Subscriptions** → `profiles`, analytics, subscriptions
  (404); Supabase Auth (email) exists but no users/roles.

## Duplicate structures flagged (not wired, to avoid duplication)
- `Park`/`parks` duplicates `destinations` (Base44 has no `parks`). Kept legacy;
  the app uses `Destination`.
- `Song`/`songs` overlaps `media`(audio). The `media`-backed path is preferred.

## Remaining manual configuration / credentials
1. **Persist keys as Secrets:** `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`
   (currently in a gitignored `.env` for this session). Keep the secret key
   server-side only.
2. **Author content in Base44** (or import) so `destinations/stops/stories/
   knowledge_articles/media` are non-empty — the app is wired but has nothing to
   show until then.
3. **Create roadmap tables via migration** (wildlife, plants, trails, songs,
   albums, radio_stations, profiles/roles, analytics) to light up those modules.
4. **RLS for writes** + an auth model if the app/admin will edit (reads already
   work for anon).

## Verification summary
- `flutter analyze`: clean. Unit tests: **10/10 pass**.
- Live reads (publishable key, browser-style): destinations/stops/stories/
  knowledge_articles/media = **200**; `mp3` bucket list = **200**;
  songs/wildlife/plants/trails/radio_stations/albums/profiles = **404** (no
  table, as expected).
