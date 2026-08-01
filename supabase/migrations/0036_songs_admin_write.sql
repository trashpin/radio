-- ExplorerOS — make the Song Importer work like the rest of the admin
--
-- The Music Library / Song Importer writes to the `songs` table. Migration 0011
-- made `songs` writable by the `authenticated` role only, but the ExplorerOS
-- admin operates with the anon/publishable key (the same way nearby_gems,
-- generation_jobs, and storage uploads already work). As a result song imports
-- fail with `42501 row-level security policy` while everything else succeeds.
--
-- This aligns `songs` with the project's admin-managed model: public read,
-- anon + authenticated write (see nearby_gems / migration 0034). The admin is
-- gated in the UI; tighten to authenticated-only in production if desired.
-- Storage (`music`/`artwork` buckets) already accepts these uploads, so only
-- the table policy needs to change.
--
-- Idempotent: safe to re-run.

alter table public.songs enable row level security;

drop policy if exists "write_songs" on public.songs;
drop policy if exists "songs_write" on public.songs;
create policy "songs_write" on public.songs
  for all to anon, authenticated using (true) with check (true);

-- keep public read
drop policy if exists "read_songs" on public.songs;
create policy "read_songs" on public.songs
  for select to anon, authenticated using (true);
