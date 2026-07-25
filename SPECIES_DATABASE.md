# Species Database (Discovery)

Supabase schema for the discovery guide. Reuses `user_favorites`; **does not
duplicate** existing tables — the new `species` table generalizes the
`wildlife`/`plants` concepts (those become category-scoped views/rows of
`species`). Create only what's missing (via a `0004_discovery.sql` migration).

## Core
- **`species`** — one row per identifiable thing (animal, bird, tree, waterfall…)
  - `species_id` uuid PK, `category` text (taxonomy token), `common_name`,
    `scientific_name`, `pronunciation`, `description`, `hero_media_id` → media,
    `size`, `weight`, `color`, `shape`, `special_markings`, `male_vs_female`,
    `juvenile_notes`, `diet`, `behavior`, `life_span`, `breeding`,
    `conservation_status`, `safety_info`, `fun_facts`, `published`,
    `created_at/updated_at`.
- **`species_images`** — `id`, `species_id` FK, `media_id`/`url`, `caption`,
  `sort_order` (gallery).
- **`species_audio`** — `id`, `species_id` FK, `kind` (narration), `url`,
  `duration_seconds` ("Hear About This").
- **`species_sounds`** — `id`, `species_id` FK, `kind` (call/song/warning),
  `url`, `duration_seconds`.
- **`species_facts`** — `id`, `species_id` FK, `label`, `value` (or typed
  columns) for the Facts section.
- **`species_comparisons`** — `id`, `species_id` FK, `compare_species_id` FK,
  `key_differences`, ordering (see `COMPARE_SYSTEM.md`).
- **`species_habitats`** — `id`, `species_id` FK, `destination_id` FK (park
  presence), `best_viewing_areas`, `nearby_habitats`, lat/lng (Where Found).
- **`species_keywords`** — `id`, `species_id` FK, `keyword` (global search).

## User data
- **`user_favorites`** — REUSED (`entity_type='species'`, `entity_id=species_id`).
- **`journal_entries`** — `id`, `user_id`, `species_id`, `note`, `photo_url`,
  `created_at` ("Save to Journal").
- **`seen_species`** — `id`, `user_id`, `species_id`, `seen_at` (Life List /
  "Mark as seen"). May be unified with the existing `explorer_sightings`.

## Relationships
```
species (species_id)
  ├─< species_images / species_audio / species_sounds / species_facts / species_keywords
  ├─< species_comparisons (species_id, compare_species_id → species)
  └─< species_habitats (destination_id → destinations)   # park presence + Where Found
user_favorites / journal_entries / seen_species → species_id  (per user)
```

## RLS
- Content tables (`species*`): public SELECT of `published = true` (like the
  destinations policy). Admin writes via authenticated role.
- User tables: `auth.uid() = user_id` for read/write once auth ships.

## Notes
- `hero_media_id`/images/audio reuse the existing `media` + `mp3` storage
  patterns and `MediaRepository`.
- "Popular in This Park" = `species_habitats` joined to the current
  `destination_id`, ordered by prevalence.
