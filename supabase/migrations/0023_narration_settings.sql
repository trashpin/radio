-- ============================================================================
-- AI Narration settings (0023) — Settings > AI Narration toggles.
-- ----------------------------------------------------------------------------
-- Single-row table holding the three automation switches. All default OFF, so
-- ExplorerOS never auto-generates scripts/audio or auto-publishes unless an
-- administrator turns a switch on. Additive + idempotent.
-- Run in the Supabase SQL editor for project qqeyvhcgirmfokoftiuz.
-- ============================================================================

create table if not exists public.narration_settings (
  id boolean primary key default true,
  auto_generate_scripts boolean not null default false,
  auto_generate_audio boolean not null default false,
  auto_publish boolean not null default false,
  updated_at timestamptz not null default now(),
  constraint narration_settings_singleton check (id)
);
comment on table public.narration_settings is
  'Single-row automation switches for the AI Narration Studio (all default OFF).';

insert into public.narration_settings (id) values (true) on conflict (id) do nothing;

do $$
begin
  if to_regprocedure('public.set_updated_at()') is not null then
    drop trigger if exists trg_set_updated_at on public.narration_settings;
    create trigger trg_set_updated_at before update on public.narration_settings
      for each row execute function public.set_updated_at();
  end if;
end $$;

alter table public.narration_settings enable row level security;
drop policy if exists "read_narration_settings" on public.narration_settings;
create policy "read_narration_settings" on public.narration_settings
  for select to anon, authenticated using (true);
drop policy if exists "write_narration_settings" on public.narration_settings;
create policy "write_narration_settings" on public.narration_settings
  for insert to anon, authenticated with check (true);
drop policy if exists "update_narration_settings" on public.narration_settings;
create policy "update_narration_settings" on public.narration_settings
  for update to anon, authenticated using (true) with check (true);
