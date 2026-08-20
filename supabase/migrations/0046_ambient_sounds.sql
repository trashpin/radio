-- ExplorerOS — Ambient sound library for Explore narration
--
-- A small, reusable library of looping background beds (flowing water,
-- birds, swamp, forest, wind, rain, horses, insects, river, lake, ...) that
-- MAY play very quietly underneath an Explore narration segment. Optional,
-- admin-authored association only -- existing content records are not
-- restructured, just given one more nullable field to point at a sound.
--
-- Idempotent: safe to re-run.

create extension if not exists "pgcrypto";

create table if not exists public.ambient_sounds (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  type        text not null,          -- flowing_water, birds, swamp, forest, ...
  audio_url   text,                   -- nullable: the admin uploader may create
                                       -- a row before attaching a clip
  active      boolean not null default true,
  description text,
  created_at  timestamptz not null default now()
);

create index if not exists ambient_sounds_type_idx on public.ambient_sounds (type);

-- Existing content can optionally point at a sound TYPE (not a specific row,
-- so an admin can add/retire individual clips within a type without editing
-- every piece of content that references it, and so several rows can share
-- one type for the "vary them" requirement).
alter table public.location_content
  add column if not exists ambient_type text;

-- RLS: public read; admin (anon/authenticated) write — mirrors location_content.
alter table public.ambient_sounds enable row level security;

do $$
begin
  execute 'drop policy if exists "ambient_sounds_read" on public.ambient_sounds';
  execute 'create policy "ambient_sounds_read" on public.ambient_sounds '
          'for select to anon, authenticated using (true)';
  execute 'drop policy if exists "ambient_sounds_write" on public.ambient_sounds';
  execute 'create policy "ambient_sounds_write" on public.ambient_sounds '
          'for insert to anon, authenticated with check (true)';
  execute 'drop policy if exists "ambient_sounds_update" on public.ambient_sounds';
  execute 'create policy "ambient_sounds_update" on public.ambient_sounds '
          'for update to anon, authenticated using (true) with check (true)';
  execute 'drop policy if exists "ambient_sounds_delete" on public.ambient_sounds';
  execute 'create policy "ambient_sounds_delete" on public.ambient_sounds '
          'for delete to anon, authenticated using (true)';
end $$;

-- Public `ambient-sounds` Storage bucket for the audio files themselves.
insert into storage.buckets (id, name, public)
values ('ambient-sounds', 'ambient-sounds', true)
on conflict (id) do nothing;

do $$
begin
  execute 'drop policy if exists "ambient_sounds_bucket_read" on storage.objects';
  execute 'create policy "ambient_sounds_bucket_read" on storage.objects '
          'for select to anon, authenticated using (bucket_id = ''ambient-sounds'')';
  execute 'drop policy if exists "ambient_sounds_bucket_write" on storage.objects';
  execute 'create policy "ambient_sounds_bucket_write" on storage.objects '
          'for insert to anon, authenticated with check (bucket_id = ''ambient-sounds'')';
  execute 'drop policy if exists "ambient_sounds_bucket_update" on storage.objects';
  execute 'create policy "ambient_sounds_bucket_update" on storage.objects '
          'for update to anon, authenticated using (bucket_id = ''ambient-sounds'')';
  execute 'drop policy if exists "ambient_sounds_bucket_delete" on storage.objects';
  execute 'create policy "ambient_sounds_bucket_delete" on storage.objects '
          'for delete to anon, authenticated using (bucket_id = ''ambient-sounds'')';
exception
  when insufficient_privilege then
    raise notice 'Skipping storage.objects policies (insufficient privilege).';
end $$;
