# Supabase Connection Analysis

Project: **`qqeyvhcgirmfokoftiuz`** (`https://qqeyvhcgirmfokoftiuz.supabase.co`)

Method: live inspection of the project's PostgREST OpenAPI, row counts
(`Content-Range`), Storage bucket list, and Auth settings — performed
**server-side from the build VM** using the available key (never from a
browser). No values were invented; anything unknown is listed under *Missing
configuration*.

---

## Is Base44 connected to this Supabase project?

**Most likely YES — Base44 appears to use this project as its database.** Evidence:
- The project already contains **Base44-style schema**: `destinations`, `stops`,
  `stories`, `knowledge_articles`, `media`, `narrations`.
- A **`radio` data-dictionary table** (24 rows of `table/field_name/data_type/
  required/description`) — a Base44 scaffolding artifact, not radio content.
- A **`visitor_csv_data`** table with **182 rows** (a Base44 CSV import) and a
  `visitor` table.
- A public **`mp3`** Storage bucket created 2026-07-24.

**Caveat (not an assumption):** the content tables are essentially **empty**
(see counts). The only rows in `destinations`/`media` are **test seeds inserted
during earlier admin verification**, not Base44-authored content. So while the
*schema/connection* looks like Base44's, there is **no evidence of Base44 having
authored park content here yet**. Definitive confirmation requires creating one
record in Base44 and checking it appears in these tables (see *Required manual
verification*).

---

## 1. Current database connection

- **Client:** `supabase_flutter` via `SupabaseService`
  (`lib/core/services/supabase_service.dart`) — a **single** shared client
  (`supabaseClientProvider`). No duplicate connections; the admin reuses this
  same doorway and the generic `SupabaseReadRepository`/`SupabaseSyncRepository`.
- **Reachability:** PostgREST responds (HTTP 200) to authenticated requests.
- **URL:** `https://qqeyvhcgirmfokoftiuz.supabase.co` (currently stored in the
  `SUPABASE_DB_URL` secret; the app reads `SUPABASE_URL`, which is empty — see
  *Missing configuration*).

## 2. Current authentication

- **Supabase Auth is available**, `email` provider **enabled**;
  `anonymous_users` **disabled**; **no OAuth providers** enabled.
- **No sign-in flow in the app/admin**, no `profiles`/roles table, no admin
  users provisioned. The admin currently has **no authentication** wired.

## 3. Current storage connection

- **Buckets:** exactly **one** — **`mp3`** (public).
- No `photos`, `videos`, `documents`, `artwork`, `logos`, or `gpx` buckets.
- The `mp3` bucket is reachable (public read); earlier testing showed uploads
  land under `mp3/demo/…`.

## 4. Existing environment variables (this environment)

| Variable | Status | Notes |
|---|---|---|
| `SUPABASE_URL` | **empty** | App reads this; must be set to the project URL |
| `SUPABASE_ANON_KEY` | set, but holds a **`sb_secret_…`** key | Wrong key type — a **secret** key, not the anon/publishable key |
| `SUPABASE_PUBLISHABLE_KEY` | **empty** | Required for the browser admin |
| `SUPABASE_SERVICE_ROLE_KEY` | empty | — |
| `SUPABASE_DB_URL` | holds the **project URL** | Misnamed; not a Postgres connection string |

The app's `.env` (gitignored) currently has blank values; `EnvConfig` reads
`SUPABASE_URL` / `SUPABASE_ANON_KEY`.

## 5. Existing API keys

- Present: **one secret key** (`sb_secret_…`, length 41), stored under
  `SUPABASE_ANON_KEY`.
- **Not present:** the **publishable/anon key** (`sb_publishable_…`).
- Supabase **blocks `sb_secret_` keys from browsers** (HTTP 401 "Forbidden use
  of secret API key in browser" — verified earlier via CDP). Therefore the
  browser admin **cannot** use the currently-supplied key.

## 6. Existing bucket usage

| Bucket | Public | Purpose (observed) |
|---|---|---|
| `mp3` | yes | audio (and, currently, the only bucket) |

## 7. Existing table usage (row counts, live)

| Table | Rows | Notes |
|---|---|---|
| `destinations` | 1 | test seed (DEMO-OCALA), not Base44 content |
| `media` | 2 | test seeds (audio) |
| `radio` | 24 | **data dictionary** (not content) |
| `visitor_csv_data` | 182 | Base44 CSV import |
| `stops` | 0 | empty |
| `stories` | 0 | empty |
| `knowledge_articles` | 0 | empty |
| `narrations` | 0 | placeholder |
| `visitor` | 0 | empty |

## 8. Row Level Security compatibility

- **Cannot be verified without the publishable/anon key.** All checks above used
  the **secret** key, which **bypasses RLS**, so a 200 here does **not** prove an
  anonymous/authenticated browser client can read/write.
- To be RLS-compatible, the project needs, per table the admin uses:
  - `SELECT` policy for the client role (anon or authenticated) — for reads.
  - `INSERT`/`UPDATE`/`DELETE` policies for authenticated admins — for CRUD.
- Storage: the `mp3` bucket is public (read OK); uploads/deletes need Storage
  policies for the client role.

---

## Missing configuration (must be supplied — not invented)

1. **`SUPABASE_PUBLISHABLE_KEY`** (`sb_publishable_…`) — the anon/publishable key
   from **Project Settings → API**. **Required** for the browser admin to talk to
   Supabase at all. The current `sb_secret_` key must **never** be used in the
   browser.
2. **`SUPABASE_URL`** — set to `https://qqeyvhcgirmfokoftiuz.supabase.co` (it is
   currently empty; the URL was placed in `SUPABASE_DB_URL`).
3. **RLS policies** — SELECT for reads; INSERT/UPDATE/DELETE for authenticated
   admins (for CRUD). Cannot be verified/authored without the publishable key +
   an auth decision.
4. **Auth model for the admin** — if the admin performs writes, it needs
   Supabase Auth sign-in + a `profiles.role` table (Administrator/Editor/…), so
   RLS can gate writes. None exists today.
5. **Additional Storage buckets** (only if those media types are used):
   `photos`, `videos`, `documents`, `artwork`, `logos`, `gpx`.
6. **Content** — Base44 (or an import) must actually populate
   `destinations`/`stops`/`stories`/`media` for the admin to display real data.

## Required manual verification

- In Base44, create/edit one destination and confirm it appears in this
  project's `destinations` table — this definitively confirms Base44↔Supabase
  content writes (vs. schema-only connection).
