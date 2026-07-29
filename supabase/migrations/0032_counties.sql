-- ExplorerOS — County Manager (County Welcome & Weather Radio personalities).
-- Editable per-county greeting, description, theme song, weather + rec toggles,
-- and a recommendation library. The radio falls back to built-in defaults when
-- a county has no row here.

create extension if not exists "pgcrypto";

create table if not exists public.counties (
  id                        uuid primary key default gen_random_uuid(),
  name                      text not null,
  state                     text not null default 'Florida',
  welcome                   text,
  description               text,
  theme_song_url            text,
  weather_voice             text,
  weather_enabled           boolean not null default true,
  recommendations_enabled   boolean not null default true,
  recommendations           text[] default '{}',
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);

create unique index if not exists counties_name_state_uidx
  on public.counties (lower(name), lower(state));

create or replace function public.counties_touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

drop trigger if exists counties_set_updated_at on public.counties;
create trigger counties_set_updated_at
  before update on public.counties
  for each row execute function public.counties_touch_updated_at();

-- Seed a few Florida county personalities (idempotent).
insert into public.counties (name, state, welcome)
values
  ('Marion', 'Florida', 'Welcome to Marion County, the Horse Capital of the World.'),
  ('Alachua', 'Florida', 'Welcome to beautiful Alachua County.'),
  ('Citrus', 'Florida', 'Welcome to Citrus County, home of Crystal River and the manatees.'),
  ('Lake', 'Florida', 'Welcome to scenic Lake County.'),
  ('Levy', 'Florida', 'Welcome to Levy County.')
on conflict do nothing;

alter table public.counties enable row level security;
do $$
begin
  execute 'drop policy if exists "counties_read" on public.counties';
  execute 'create policy "counties_read" on public.counties for select to anon, authenticated using (true)';
  execute 'drop policy if exists "counties_write" on public.counties';
  execute 'create policy "counties_write" on public.counties for insert to anon, authenticated with check (true)';
  execute 'drop policy if exists "counties_update" on public.counties';
  execute 'create policy "counties_update" on public.counties for update to anon, authenticated using (true) with check (true)';
  execute 'drop policy if exists "counties_delete" on public.counties';
  execute 'create policy "counties_delete" on public.counties for delete to anon, authenticated using (true)';
end $$;
