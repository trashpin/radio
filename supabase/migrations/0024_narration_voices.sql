-- ============================================================================
-- Narration voice selection (0024)
-- ----------------------------------------------------------------------------
-- Per-narration voice + a resolution chain of default voices (per-destination /
-- county / park / global). Audio generation uses the resolved voice — no
-- hardcoded default. Additive + idempotent.
-- Run in the Supabase SQL editor for project qqeyvhcgirmfokoftiuz.
-- ============================================================================

create extension if not exists pgcrypto;

-- Per-narration voice + when the audio was generated.
alter table public.destination_narrations add column if not exists voice_id text;
alter table public.destination_narrations add column if not exists audio_generated_at timestamptz;

-- Global default voice (on the settings singleton from 0023).
alter table public.narration_settings add column if not exists default_voice_id text;
alter table public.narration_settings add column if not exists default_voice_name text;

-- Scope-based voice overrides: destination / county / park. Open RLS to match
-- the app's admin-write pattern (avoids depending on destinations write RLS).
create table if not exists public.voice_defaults (
  id uuid primary key default gen_random_uuid(),
  scope text not null,          -- 'destination' | 'county' | 'park'
  scope_value text not null,    -- destination_id | county name | park code
  voice_id text not null,
  voice_name text,
  updated_at timestamptz not null default now(),
  unique (scope, scope_value)
);
comment on table public.voice_defaults is
  'Default narration voice per scope (destination/county/park). Resolution: '
  'narration.voice_id → destination → park → county → global (narration_settings).';
create index if not exists idx_voice_defaults on public.voice_defaults (scope, scope_value);

do $$
begin
  if to_regprocedure('public.set_updated_at()') is not null then
    drop trigger if exists trg_set_updated_at on public.voice_defaults;
    create trigger trg_set_updated_at before update on public.voice_defaults
      for each row execute function public.set_updated_at();
  end if;
end $$;

alter table public.voice_defaults enable row level security;
drop policy if exists "read_voice_defaults" on public.voice_defaults;
create policy "read_voice_defaults" on public.voice_defaults for select to anon, authenticated using (true);
drop policy if exists "write_voice_defaults" on public.voice_defaults;
create policy "write_voice_defaults" on public.voice_defaults for insert to anon, authenticated with check (true);
drop policy if exists "update_voice_defaults" on public.voice_defaults;
create policy "update_voice_defaults" on public.voice_defaults for update to anon, authenticated using (true) with check (true);
drop policy if exists "delete_voice_defaults" on public.voice_defaults;
create policy "delete_voice_defaults" on public.voice_defaults for delete to anon, authenticated using (true);
