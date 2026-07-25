# Species Sync — Base44 → Supabase `species`

How Base44 imports (e.g. the Ocala Plants CSV) should write into the master
`species` table (run `supabase/migrations/0004_species.sql` first).

## Target
- **Table:** `species` (NOT `media`). One row per plant/tree/bird/etc.
- **Assets:** any photo/audio/video goes to `media` with `species_id` set to the
  new species row's id (or set `species.hero_image` to a direct public URL).

## Field mapping (CSV column → `species` column)
| CSV / Base44 field | `species` column | Notes |
|---|---|---|
| Category (or fixed "Plants") | `category` | token: `plants`,`trees`,`birds`,`mammals`,`reptiles`,`amphibians`,`fish`,`insects`,`mushrooms`,`wildflowers`,`animal_tracks`,`historic_sites`,`scenic_views`,`waterfalls`,`springs`,`trail_features` |
| Common Name | `common_name` | required |
| Scientific Name | `scientific_name` | |
| Pronunciation | `pronunciation` | |
| Description | `description` | |
| Size / Color / Shape / … | `size`,`color`,`shape`,… | identification |
| Diet / Behavior / Lifespan / Conservation / Fun Facts | `diet`,`behavior`,`life_span`,`conservation_status`,`fun_facts` | facts |
| Photo URL | `hero_image` **or** a `media` row (`media.species_id`, `media_type='photo'`, `file_url`) + `species.hero_media_id` | keep species out of media |
| Park | `destination_id` | Ocala = `8338b34e-4d8f-4ff8-a8a3-13b7d82feba2` |
| Published | `published` | default true |

## Base44 sync process (update the existing importer)
1. Reuse the connector pattern from the working **songMediaSync** (same Supabase
   project + service key, server-side).
2. Add a **speciesSync** that, per imported row:
   - `insert into species (...)` using the mapping above (returns `species_id`);
   - for each image, upload to storage and `insert into media (species_id, media_type='photo', file_url, ...)`; optionally set `species.hero_media_id`.
3. Point the **Plants / nature importers** at `speciesSync` (not the media importer).

## Verification
After running the migration + a Base44 import, the rows are queryable at
`/rest/v1/species?category=eq.plants&destination_id=eq.<ocala>` and appear in
the Flutter app: Home → **I See Something** → **Plants**.
