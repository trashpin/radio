-- Radio Scheduler — professional rundown builder.
--
-- A `rundown` is a named, schedulable log ("clock") of items to air in order;
-- `rundown_items` are its timeline rows. Reuses the existing audio engine at
-- runtime — this migration only stores the schedule. Additive + idempotent;
-- RLS mirrors the project's admin model (public read, anon+authenticated write).

create table if not exists public.rundowns (
  id           uuid primary key default gen_random_uuid(),
  name         text not null default 'Untitled rundown',
  scheduled_at timestamptz,
  recurrence   text not null default 'none',   -- none|daily|weekdays|weekly|monthly
  published    boolean not null default false,
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table if not exists public.rundown_items (
  id               uuid primary key default gen_random_uuid(),
  rundown_id       uuid not null references public.rundowns(id) on delete cascade,
  type             text not null default 'custom_audio',
  name             text not null default '',
  sort_order       integer not null default 0,
  duration_seconds integer not null default 0,
  enabled          boolean not null default true,
  audio_url        text,
  script           text,
  ref_id           text,        -- optional link to a location/event/etc.
  created_at       timestamptz not null default now()
);

create index if not exists rundown_items_rundown_idx
  on public.rundown_items (rundown_id, sort_order);

alter table public.rundowns enable row level security;
alter table public.rundown_items enable row level security;

drop policy if exists "read_rundowns" on public.rundowns;
create policy "read_rundowns" on public.rundowns for select using (true);
drop policy if exists "write_rundowns" on public.rundowns;
create policy "write_rundowns" on public.rundowns for all
  to anon, authenticated using (true) with check (true);

drop policy if exists "read_rundown_items" on public.rundown_items;
create policy "read_rundown_items" on public.rundown_items for select using (true);
drop policy if exists "write_rundown_items" on public.rundown_items;
create policy "write_rundown_items" on public.rundown_items for all
  to anon, authenticated using (true) with check (true);
