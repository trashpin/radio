# ExplorerOS — Supabase backend

Schema and demo seed for the ExplorerOS content + user data.

## Files
- `migrations/0001_exploreros_schema.sql` — core tables + Row Level Security
  (content tables are anon-readable; user tables are demo-open — tighten to
  `auth.uid()` once auth is added).
- `migrations/0002_music_library.sql` — Music Management tables (albums, genres,
  moods, artworks, music_metadata, playlists, station_assignments,
  gps_music_triggers, upload_jobs).
- `seed.sql` — a self-consistent demo dataset (Florida → Ocala → springs, an
  Explorer Radio station with real sample audio) so the app has live content.

## Storage buckets (for Music Management)
Create two public buckets in Supabase Storage: `music_audio` and
`music_artwork`. Bulk import uploads audio/art there and stores the public URLs
in the database.

## Apply

Option A — Supabase SQL editor: paste `migrations/0001_exploreros_schema.sql`
then `seed.sql` and run.

Option B — Supabase CLI:

```
supabase db push        # or: psql "$DATABASE_URL" -f migrations/0001_exploreros_schema.sql
psql "$DATABASE_URL" -f supabase/seed.sql
```

## Connect the app
The app reads `SUPABASE_URL` / `SUPABASE_ANON_KEY` from a gitignored `.env`
(loaded by `flutter_dotenv`). In Cursor Cloud, add them as **Secrets**; the
startup script writes them into `.env` automatically. Locally, copy
`.env.example` → `.env` and fill them in. With keys set and the schema applied,
Explore lists destinations, and the Radio/GPS engines have real content to play.

## Column contract
Table columns match each Dart model's `fromJson`/`toJson` keys exactly
(snake_case). If you change a model, update the matching table here.
