-- ============================================================================
-- Destination write access (0021)
-- ----------------------------------------------------------------------------
-- The in-app admin (Destination dashboard + CSV importer) needs to create,
-- import, edit, and delete destinations. `destinations` already has public READ
-- (migration 0001) but no write policy, so inserts/updates fail with
-- "42501 new row violates row-level security policy". This adds insert/update/
-- delete for the admin, matching the permissive write pattern used by the other
-- content tables (0010/0019/0020). Idempotent — safe to run and re-run.
-- Run in the Supabase SQL editor for project qqeyvhcgirmfokoftiuz.
-- ============================================================================

do $$
begin
  if to_regclass('public.destinations') is not null then
    execute 'alter table public.destinations enable row level security';

    -- Preserve the existing public read policy; ensure one exists.
    execute 'drop policy if exists "destinations_public_read" on public.destinations';
    execute 'create policy "destinations_public_read" on public.destinations '
            'for select to anon, authenticated using (true)';

    execute 'drop policy if exists "destinations_write" on public.destinations';
    execute 'create policy "destinations_write" on public.destinations '
            'for insert to anon, authenticated with check (true)';

    execute 'drop policy if exists "destinations_update" on public.destinations';
    execute 'create policy "destinations_update" on public.destinations '
            'for update to anon, authenticated using (true) with check (true)';

    execute 'drop policy if exists "destinations_delete" on public.destinations';
    execute 'create policy "destinations_delete" on public.destinations '
            'for delete to anon, authenticated using (true)';
  end if;
end $$;
