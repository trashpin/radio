# ExplorerOS — Music Library Architecture

Music Management is the central library that Explorer Radio draws from. It owns
songs, albums, artwork, metadata, playlists, station assignments, GPS-triggered
songs, and bulk import — designed for **thousands of songs and hundreds of
stations**, stored in Supabase (metadata in the database, audio/art in Storage).

---

## 1. Folder structure

`lib/features/music/`

| Folder | Responsibility |
| --- | --- |
| `models/` | `Album`, `Genre`, `Mood`, `Artwork`, `MusicMetadata`, `Playlist`, `StationAssignment`, `GPSMusicTrigger`, `UploadJob` (+ reuses the shared `Song`). |
| `repositories/` | Data access per entity + the `MusicRepository` facade. |
| `services/` | `MusicLibraryService`, `SongService`, `ArtworkService`, `MetadataService`, `MusicStorageService`, `MusicWriter`. |
| `albums/` | `AlbumService`. |
| `playlists/` | `PlaylistService`. |
| `stations/` | `StationAssignmentService`. |
| `importers/` | `CSVImporter`, `ZIPImporter`, `BulkImportService`. |
| `controllers/` | `MusicLibraryController` (Riverpod `Notifier`). |
| `providers/` | DI wiring (co-located with each service/repo). |
| `utils/` | Helpers. |
| `documentation/` | This document. |

---

## 2. Model relationships

```
Album 1───* MusicMetadata *───1 Song
Genre 1───* MusicMetadata
Mood  1───* MusicMetadata
Artwork 1──* MusicMetadata / Album
Song *──────* RadioStation   (via StationAssignment)
Song 1──────* GPSMusicTrigger
Playlist *──* Song           (ordered song_ids)
```

The shared `Song` is the playable track (title/artist/audio_url/duration). Rich
attributes live in `MusicMetadata` (keyed by `song_id`) so tracks can be
enriched — including by future AI tagging (`ai_tagged`) — without changing the
core record. Stations are decoupled from songs via `StationAssignment`
(many-to-many, weighted).

---

## 3. Storage strategy

- **Audio + artwork bytes → Supabase Storage** (`music_audio`, `music_artwork`
  buckets) via `MusicStorageService`, which returns the public URL.
- **Metadata → Supabase Database** (the tables above). `Song.audioUrl` /
  `Artwork.url` point at the Storage objects. The app/engine never read files
  directly — only URLs.

---

## 4. Bulk import

`BulkImportService` runs the pipeline and returns an `UploadJob` (progress/
status):
- **CSV** (`CSVImporter`, pure): header-mapped rows → song rows (+ metadata tags
  for album/genre/mood) → `MusicWriter.upsertSongs/upsertMetadata`.
- **ZIP** (`ZIPImporter`, pure): extract audio entries → `MusicStorageService`
  upload → song rows → `MusicWriter`.
`MusicWriter` is an abstraction (`SupabaseMusicWriter` in prod, a fake in tests),
so import is unit-testable without network. Writes require admin/authenticated
access at runtime.

---

## 5. Integration with Explorer Radio

The Radio Engine queries the **`MusicRepository`**, never files:
`MusicRepository.songsForStation(stationId)` resolves a station's playlist from
explicit `StationAssignment`s (falling back to a song's own `stationId`). The app
loads the engine's `StationManager` from this result, so swapping/growing the
library requires no engine changes. GPS-triggered songs (`GPSMusicTrigger`) feed
the GPS→AI-Producer→Radio path alongside narration triggers.

---

## 6. Offline downloads

Songs resolve to a Storage URL; the radio `OfflinePlaybackService` registry
records downloaded files so playback prefers a local path with no signal. The
download manager (future) fetches `Song.audioUrl` → local file → registers it.

---

## 7. Scalability

- Data-driven and paged: repositories sit on the generic Supabase base (cache +
  offline fallback); add pagination/range queries for very large catalogs.
- `StationAssignment` weights + `MusicMetadata` (genre/mood/bpm) enable smart,
  data-driven station selection (evolve `MusicScheduler` to consume them).
- Import is job-based (`UploadJob`) and resumable in principle; batch writes.
- Storage scales independently of the database; artwork/audio are CDN-served
  public URLs.

---

## 8. Future AI metadata tagging

`MusicMetadata.aiTagged` + `MetadataService.tag(...)` are the seam: an AI
pipeline can enrich tags/genre/mood/bpm post-import without touching songs or
the engine.
