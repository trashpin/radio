# Offline Strategy (Discovery)

Downloaded parks must let visitors identify species with no signal. The
discovery guide is read-mostly, so offline = a per-park content bundle + a
cache-first repository layer.

## What a downloaded park includes
- Species rows for the park (via `species_habitats.destination_id`)
- Species images + gallery (the `mp3`/species image assets)
- Descriptions, identification, facts
- Narration audio ("Hear About This") + species sounds
- Comparison data (`species_comparisons` for included species)
- Where-Found map data (habitats, best viewing areas)

## Mechanism (reuses existing seams)
- The app already has a `CacheStore` abstraction (`InMemoryCacheStore`) behind
  `SupabaseReadRepository`, and a `Download`/`DownloadRepository` +
  `OfflinePlaybackService` (radio). Offline discovery reuses these:
  1. **Download job** (existing `downloads` table + repository) enumerates a
     park's species + related rows and their media URLs.
  2. **Persistent cache**: swap `InMemoryCacheStore` for a persistent store
     (Hive/sqflite/files) — zero repository changes (the seam already exists).
  3. **Media**: download images/audio to app storage; `MediaRepository.resolveUrl`
     returns local paths when available (mirrors `OfflinePlaybackService`).
- **Read path**: repositories serve cache when offline or on network failure
  (already implemented in `SupabaseReadRepository.getAll`), so screens work
  unchanged offline.

## Sync of user data
Favorites / journal / seen created offline are queued locally and upserted when
back online (the sighting service already degrades gracefully on write failure —
same pattern: keep locally, sync later).

## Future
- Offline AI identification (on-device model) behind the
  `SpeciesIdentificationService` seam.
- Delta updates per park (only changed species) using `updated_at`.
