-- ExplorerOS — Local Events (highest-priority tier for the location-aware
-- player: EVENT -> PARK -> SPRING -> TOWN -> COUNTY).
--
-- A lightweight, standalone content-support table (public read, open write —
-- same pattern as `businesses`/`images`/`videos` from migration 0019).
-- Optionally links to a master `locations` row via location_id so an event
-- can inherit that location's coordinates/imagery, but never requires one —
-- a one-off event (a fair, a concert) is its own record.
--
-- Additive + idempotent: safe to re-run.

create extension if not exists "pgcrypto";

create table if not exists public.events (
  id                uuid primary key default gen_random_uuid(),
  name              text not null,
  description       text,
  short_description text,
  image_url         text,
  latitude          double precision,
  longitude         double precision,
  location_id       uuid references public.locations(id) on delete set null,
  county            text,
  city              text,
  event_date        date,
  start_time        time,
  end_time          time,
  external_website  text,
  source            text,
  source_id         text,
  active            boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index if not exists events_date_idx on public.events (event_date);
create index if not exists events_latlng_idx on public.events (latitude, longitude);
create index if not exists events_active_idx on public.events (active);

create or replace function public.events_touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

drop trigger if exists events_set_updated_at on public.events;
create trigger events_set_updated_at
  before update on public.events
  for each row execute function public.events_touch_updated_at();

alter table public.events enable row level security;
do $$
begin
  execute 'drop policy if exists "events_read" on public.events';
  execute 'create policy "events_read" on public.events for select to anon, authenticated using (true)';
  execute 'drop policy if exists "events_write" on public.events';
  execute 'create policy "events_write" on public.events for insert to anon, authenticated with check (true)';
  execute 'drop policy if exists "events_update" on public.events';
  execute 'create policy "events_update" on public.events for update to anon, authenticated using (true) with check (true)';
  execute 'drop policy if exists "events_delete" on public.events';
  execute 'create policy "events_delete" on public.events for delete to anon, authenticated using (true)';
end $$;
