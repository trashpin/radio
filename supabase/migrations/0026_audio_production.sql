-- ExplorerOS — Audio Production Studio
--
-- A permanent catalog of generated narration audio for every record, plus a
-- per-category default-voice map. Files live in the public `audio` Storage
-- bucket, organized by category folders (parks/, wildlife/, plants/, …).
--
-- Generation itself runs server-side (the narration worker draining
-- `generation_jobs`); this module is the admin control surface + catalog.
-- Idempotent: safe to re-run.

create extension if not exists "pgcrypto";

create table if not exists public.audio_assets (
  id                 uuid primary key default gen_random_uuid(),

  -- What this audio belongs to.
  record_id          text,
  record_type        text,          -- 'parks','wildlife','plants','stories',…
  destination_code   text,          -- the canonical destination anchor
  category           text,          -- voice/content category (welcome, safety…)

  -- Production metadata.
  voice              text,          -- voice id
  voice_name         text,
  provider           text default 'elevenlabs', -- elevenlabs|openai|google|polly|azure
  language           text default 'en',

  -- Where the bytes live.
  storage_path       text,
  public_url         text,
  duration           double precision, -- seconds
  file_size          bigint,

  generation_version integer not null default 1,
  status             text not null default 'pending', -- pending|generating|complete|failed
  generated_at       timestamptz,

  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index if not exists audio_assets_record_idx
  on public.audio_assets (record_type, record_id);
create index if not exists audio_assets_destination_idx
  on public.audio_assets (destination_code);
create index if not exists audio_assets_status_idx
  on public.audio_assets (status);
create index if not exists audio_assets_url_idx
  on public.audio_assets (public_url);

create or replace function public.audio_assets_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists audio_assets_set_updated_at on public.audio_assets;
create trigger audio_assets_set_updated_at
  before update on public.audio_assets
  for each row execute function public.audio_assets_touch_updated_at();

-- Default voice per content category (Voice Library).
create table if not exists public.voice_category_defaults (
  category    text primary key,      -- 'park_welcome','wildlife','plants',…
  voice_id    text,
  voice_name  text,
  provider    text default 'elevenlabs',
  updated_at  timestamptz not null default now()
);

-- RLS: public read; admin (anon/authenticated) write (mirrors other admin
-- tables — tighten to authenticated-only in production).
alter table public.audio_assets enable row level security;
alter table public.voice_category_defaults enable row level security;

do $$
declare t text;
begin
  foreach t in array array['audio_assets', 'voice_category_defaults'] loop
    execute format('drop policy if exists "%1$s_read" on public.%1$s', t);
    execute format('create policy "%1$s_read" on public.%1$s '
                   'for select to anon, authenticated using (true)', t);
    execute format('drop policy if exists "%1$s_write" on public.%1$s', t);
    execute format('create policy "%1$s_write" on public.%1$s '
                   'for insert to anon, authenticated with check (true)', t);
    execute format('drop policy if exists "%1$s_update" on public.%1$s', t);
    execute format('create policy "%1$s_update" on public.%1$s '
                   'for update to anon, authenticated using (true) with check (true)', t);
    execute format('drop policy if exists "%1$s_delete" on public.%1$s', t);
    execute format('create policy "%1$s_delete" on public.%1$s '
                   'for delete to anon, authenticated using (true)', t);
  end loop;
end $$;

-- Public `audio` Storage bucket (files organized by category folders).
insert into storage.buckets (id, name, public)
values ('audio', 'audio', true)
on conflict (id) do nothing;

do $$
begin
  execute 'drop policy if exists "audio_bucket_read" on storage.objects';
  execute 'create policy "audio_bucket_read" on storage.objects '
          'for select to anon, authenticated using (bucket_id = ''audio'')';
  execute 'drop policy if exists "audio_bucket_write" on storage.objects';
  execute 'create policy "audio_bucket_write" on storage.objects '
          'for insert to anon, authenticated with check (bucket_id = ''audio'')';
  execute 'drop policy if exists "audio_bucket_update" on storage.objects';
  execute 'create policy "audio_bucket_update" on storage.objects '
          'for update to anon, authenticated using (bucket_id = ''audio'')';
  execute 'drop policy if exists "audio_bucket_delete" on storage.objects';
  execute 'create policy "audio_bucket_delete" on storage.objects '
          'for delete to anon, authenticated using (bucket_id = ''audio'')';
exception
  when insufficient_privilege then
    raise notice 'Skipping storage.objects policies (insufficient privilege).';
end $$;
