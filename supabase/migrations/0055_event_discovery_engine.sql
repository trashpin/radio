-- Marion County Event Discovery Engine: Multiple Sources -> Discovery Engine
-- -> Verification -> Deduplication -> Admin Approval -> events -> Discover.
-- Ticketmaster becomes Source #1 through this pipeline instead of writing
-- directly into `events`; additional sources plug in the same way later
-- without any of this schema changing. Purely additive -- `events` itself
-- is untouched.

create extension if not exists pg_trgm;

create table if not exists public.event_sources (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  source_key text not null unique,       -- stable machine key, e.g. 'ticketmaster'
  source_type text not null,             -- 'api' | 'manual' | 'ai_discovery' (future)
  source_url text,
  enabled boolean not null default true,
  -- Every source starts requiring admin review; a source only skips review
  -- once its quality is proven over time (spec: "do not automatically
  -- publish everything from newly added sources until we know the source
  -- quality is reliable").
  auto_publish boolean not null default false,
  last_checked_at timestamptz,
  last_success_at timestamptz,
  last_error text,
  last_run_discovered int not null default 0,
  last_run_new int not null default 0,
  last_run_duplicates int not null default 0,
  last_run_needs_review int not null default 0,
  last_run_rejected int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.discovered_events (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references public.event_sources(id) on delete cascade,
  source_event_id text,
  source_url text,
  status text not null default 'needs_review'
    check (status in ('needs_review','verified','rejected','duplicate','published')),
  rejection_reason text,
  duplicate_of_event_id uuid references public.events(id),
  duplicate_of_discovered_id uuid references public.discovered_events(id),
  match_confidence numeric,
  published_event_id uuid references public.events(id),

  -- Normalized fields (spec's minimum capture list). Null whenever the
  -- source itself didn't provide the value -- never invented.
  name text not null,
  description text,
  start_date date,
  end_date date,
  start_time time,
  end_time time,
  venue_name text,
  address text,
  city text,
  zip text,
  latitude double precision,
  longitude double precision,
  county text,
  website text,
  ticket_url text,
  image_url text,
  organizer text,
  contact text,
  cost_info text,
  category text,
  interest_tags text[] not null default '{}',

  raw_payload jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists discovered_events_source_idx on public.discovered_events(source_id);
create index if not exists discovered_events_status_idx on public.discovered_events(status);
create index if not exists discovered_events_name_trgm_idx
  on public.discovered_events using gin (name gin_trgm_ops);
create unique index if not exists discovered_events_source_unique
  on public.discovered_events(source_id, source_event_id)
  where source_event_id is not null;

-- Internal operational tables -- no anon access (unlike public content
-- tables such as locations/categories); authenticated matches this app's
-- existing convention of gating admin screens client-side rather than via
-- a DB-level role function (no `is_admin()` exists in this project today).
alter table public.event_sources enable row level security;
alter table public.discovered_events enable row level security;
do $$
begin
  execute 'drop policy if exists "event_sources_authenticated_all" on public.event_sources';
  execute 'create policy "event_sources_authenticated_all" on public.event_sources for all to authenticated using (true) with check (true)';

  execute 'drop policy if exists "discovered_events_authenticated_all" on public.discovered_events';
  execute 'create policy "discovered_events_authenticated_all" on public.discovered_events for all to authenticated using (true) with check (true)';
end $$;

insert into public.event_sources (name, source_key, source_type, source_url, enabled)
values ('Ticketmaster', 'ticketmaster', 'api', 'https://app.ticketmaster.com/discovery/v2/events.json', true)
on conflict (source_key) do nothing;

insert into public.event_sources (name, source_key, source_type, source_url, enabled, auto_publish)
values ('Manual Entry (Admin)', 'manual', 'manual', null, true, true)
on conflict (source_key) do nothing;

-- Disclosed non-automatable sources, researched and recorded rather than
-- silently skipped (spec: "identify what nightlife-specific data sources
-- exist" / "document what needs to be added"). Each carries the concrete
-- reason no automated connector was written -- last_error is used here as
-- a durable research note, not a real run failure. Left disabled; an admin
-- can flip `enabled` once a real feed or submission workflow exists.
insert into public.event_sources (name, source_key, source_type, source_url, enabled, last_error)
values
  ('Ocala/Marion Visitors Bureau', 'visitors_bureau', 'manual', 'https://ocalamarion.com',
   'No RSS/iCal/JSON feed found on ocalamarion.com as of 2026-08-23. Has a "Submit Your Event" '
   'form -- recommend manual admin review of submissions rather than scraping.'),
  ('Marion County Government', 'marion_county_gov', 'manual', 'https://www.marionfl.org',
   'CivicPlus-based calendar; site returns HTTP 403 to automated requests as of 2026-08-23 '
   '(actively blocks scraping). Also requires filtering out government meetings/hearings per '
   'spec -- not just a feed problem. Recommend manual admin curation.'),
  ('City of Ocala', 'city_of_ocala', 'manual', 'https://ocalafl.gov',
   'No RSS/iCal/JSON feed found; site returns HTTP 403 to automated requests as of 2026-08-23. '
   'Recommend manual admin curation.')
on conflict (source_key) do nothing;
