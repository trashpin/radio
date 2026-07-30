-- ExplorerOS — Media Search Center
--
-- Extends `media_assets` (0025) with the attribution + versioning columns the
-- Media Search Center needs when importing open-license images from Openverse /
-- Wikimedia Commons (and future providers). Idempotent — safe to re-run.

alter table public.media_assets
  add column if not exists medium_url    text,   -- 1200px working copy
  add column if not exists source        text,   -- 'openverse' | 'wikimedia' | 'upload' | …
  add column if not exists original_url  text,   -- the source's original image URL
  add column if not exists license_url   text,   -- link to the license terms
  add column if not exists creator       text,   -- author/creator (alias of photographer)
  add column if not exists imported_at   timestamptz;

create index if not exists media_assets_source_idx
  on public.media_assets (source);
create index if not exists media_assets_imported_idx
  on public.media_assets (imported_at desc);

-- Convenience view: recently imported images with their destination + license
-- for the "Recently Imported" tab and the media dashboard.
create or replace view public.media_recently_imported as
  select
    m.id, m.destination_id, m.record_type, m.title, m.public_url, m.thumbnail,
    m.photographer, m.creator, m.license, m.license_url, m.source,
    m.original_url, m.width, m.height, m.file_size, m.is_hero,
    coalesce(m.imported_at, m.created_at) as imported_at
  from public.media_assets m
  where m.media_type = 'image'
  order by coalesce(m.imported_at, m.created_at) desc;
