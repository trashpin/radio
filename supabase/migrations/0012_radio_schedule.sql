-- Programming schedule: rules that decide what plays when on the radio.
-- Run in the Supabase SQL editor for project qqeyvhcgirmfokoftiuz.

create table if not exists public.radio_schedule (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  station text,
  park_code text,
  content_type text not null default 'safety',  -- safety | wildlife | story | station_id
  content_id text,                                -- optional specific item id
  cadence text not null default 'interval',       -- interval | hourly | time_of_day
  interval_minutes integer default 15,
  time_of_day text,                               -- 'HH:MM' when cadence=time_of_day
  priority integer default 5,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.radio_schedule enable row level security;
drop policy if exists "read_radio_schedule" on public.radio_schedule;
create policy "read_radio_schedule" on public.radio_schedule
  for select to anon, authenticated using (true);
drop policy if exists "write_radio_schedule" on public.radio_schedule;
create policy "write_radio_schedule" on public.radio_schedule
  for all to authenticated using (true) with check (true);
