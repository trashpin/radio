# ExplorerOS — Supabase backend

Schema and demo seed for the ExplorerOS content + user data.

## Files
- `migrations/0001_exploreros_schema.sql` — all tables + Row Level Security
  (content tables are anon-readable; user tables are demo-open — tighten to
  `auth.uid()` once auth is added).
- `seed.sql` — a self-consistent demo dataset (Florida → Ocala → springs, an
  Explorer Radio station with real sample audio) so the app has live content.

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
