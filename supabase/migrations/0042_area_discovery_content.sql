-- ExplorerOS — "Discover This Area", Phase 3: narrated content blocks.
--
-- History/Nature/Geology (unlike Wildlife/Birds/Plants, which reuse the
-- existing Species tables, and Attractions, which reuses Master Locations
-- directly) have no existing content home — this table is it. Deliberately
-- generic (category_token is free text, not an enum) so adding a brand-new
-- discovery category later (Architecture, Ghost Stories, Local Legends...)
-- never requires a schema change — exactly the spec's "Future Categories...
-- configurable through the Admin Panel" requirement.
--
-- One area can have several blocks per category (e.g. History might have
-- "Early Settlement", "Native American History", "Railroads" as separate
-- sequential blocks) — sort_order controls playback order.
--
-- Idempotent: safe to re-run.

create extension if not exists "pgcrypto";

create table if not exists public.area_discovery_content (
  id                uuid primary key default gen_random_uuid(),
  location_id       uuid not null references public.locations(id) on delete cascade,
  category_token    text not null, -- matches AreaDiscoveryCategory.token, e.g. 'history'
  title             text not null,
  narration_script  text,
  audio_url         text,
  images            text[] not null default '{}',
  sort_order        integer not null default 0,
  active            boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index if not exists area_discovery_content_location_idx
  on public.area_discovery_content (location_id);
create index if not exists area_discovery_content_category_idx
  on public.area_discovery_content (location_id, category_token, sort_order);

create or replace function public.area_discovery_content_touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

drop trigger if exists area_discovery_content_set_updated_at
  on public.area_discovery_content;
create trigger area_discovery_content_set_updated_at
  before update on public.area_discovery_content
  for each row execute function public.area_discovery_content_touch_updated_at();

alter table public.area_discovery_content enable row level security;
do $$
begin
  execute 'drop policy if exists "area_discovery_content_read" on public.area_discovery_content';
  execute 'create policy "area_discovery_content_read" on public.area_discovery_content for select to anon, authenticated using (true)';
  execute 'drop policy if exists "area_discovery_content_write" on public.area_discovery_content';
  execute 'create policy "area_discovery_content_write" on public.area_discovery_content for insert to anon, authenticated with check (true)';
  execute 'drop policy if exists "area_discovery_content_update" on public.area_discovery_content';
  execute 'create policy "area_discovery_content_update" on public.area_discovery_content for update to anon, authenticated using (true) with check (true)';
  execute 'drop policy if exists "area_discovery_content_delete" on public.area_discovery_content';
  execute 'create policy "area_discovery_content_delete" on public.area_discovery_content for delete to anon, authenticated using (true)';
end $$;
