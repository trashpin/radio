-- ExplorerOS — Media Manager
--
-- A single, normalized catalog of every media asset (hero/gallery images,
-- video, audio, ambient, AI narration, PDFs) attached to any content record
-- (species, map_locations, destinations, …). The admin "Media Manager" module
-- reads/writes this table and stores the files in the public `media` Storage
-- bucket, organized by category folders (animals/, birds/, plants/, …).
--
-- Idempotent: safe to re-run.

create extension if not exists "pgcrypto";

create table if not exists public.media_assets (
  id            uuid primary key default gen_random_uuid(),

  -- What this media is attached to.
  record_id     text,                       -- id of the owning content row
  record_type   text,                       -- 'animals','birds','trails',…
  destination_id text,                       -- owning destination, when known

  -- What kind of media this is.
  media_type    text not null default 'image', -- image|video|audio|ambient|narration|document

  -- Where the bytes live.
  storage_path  text,                        -- path within the `media` bucket
  public_url    text,                        -- resolved public URL
  thumbnail     text,                        -- thumbnail URL (image previews)

  -- Descriptive metadata.
  title         text,
  caption       text,
  photographer  text,
  copyright     text,
  license       text,
  alt_text      text,
  tags          text[] default '{}',

  -- Technical metadata.
  width         integer,
  height        integer,
  file_size     bigint,

  -- Optional geotag.
  latitude      double precision,
  longitude     double precision,

  -- Role hint so the auditor can tell a hero from a gallery image.
  is_hero       boolean not null default false,

  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists media_assets_record_idx
  on public.media_assets (record_type, record_id);
create index if not exists media_assets_destination_idx
  on public.media_assets (destination_id);
create index if not exists media_assets_type_idx
  on public.media_assets (media_type);
create index if not exists media_assets_url_idx
  on public.media_assets (public_url);

-- keep updated_at fresh
create or replace function public.media_assets_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists media_assets_set_updated_at on public.media_assets;
create trigger media_assets_set_updated_at
  before update on public.media_assets
  for each row execute function public.media_assets_touch_updated_at();

-- Row-level security: public read; admin (anon/authenticated) write. This
-- mirrors the access model used by the other admin-managed tables in this
-- project (see 0010/0021); tighten to authenticated-only in production.
alter table public.media_assets enable row level security;

drop policy if exists "media_assets_read" on public.media_assets;
create policy "media_assets_read" on public.media_assets
  for select to anon, authenticated using (true);

drop policy if exists "media_assets_insert" on public.media_assets;
create policy "media_assets_insert" on public.media_assets
  for insert to anon, authenticated with check (true);

drop policy if exists "media_assets_update" on public.media_assets;
create policy "media_assets_update" on public.media_assets
  for update to anon, authenticated using (true) with check (true);

drop policy if exists "media_assets_delete" on public.media_assets;
create policy "media_assets_delete" on public.media_assets
  for delete to anon, authenticated using (true);

-- Public `media` Storage bucket (files organized by category folders).
insert into storage.buckets (id, name, public)
values ('media', 'media', true)
on conflict (id) do nothing;

-- Storage policies for the `media` bucket.
do $$
begin
  execute 'drop policy if exists "media_bucket_read" on storage.objects';
  execute 'create policy "media_bucket_read" on storage.objects '
          'for select to anon, authenticated using (bucket_id = ''media'')';

  execute 'drop policy if exists "media_bucket_write" on storage.objects';
  execute 'create policy "media_bucket_write" on storage.objects '
          'for insert to anon, authenticated with check (bucket_id = ''media'')';

  execute 'drop policy if exists "media_bucket_update" on storage.objects';
  execute 'create policy "media_bucket_update" on storage.objects '
          'for update to anon, authenticated using (bucket_id = ''media'')';

  execute 'drop policy if exists "media_bucket_delete" on storage.objects';
  execute 'create policy "media_bucket_delete" on storage.objects '
          'for delete to anon, authenticated using (bucket_id = ''media'')';
exception
  when insufficient_privilege then
    raise notice 'Skipping storage.objects policies (insufficient privilege).';
end $$;
