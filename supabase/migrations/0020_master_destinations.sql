-- ============================================================================
-- ExplorerOS Master Destination System (0020)
-- ----------------------------------------------------------------------------
-- Turns `destinations` into the central source of truth for every destination
-- type (Florida State Parks → National Parks/Forests, springs, WMAs, scenic
-- drives, historic sites, museums, cities, beaches, campgrounds, trailheads,
-- businesses …) and scales to all 50 states / 100k+ rows without a redesign.
--
-- ADDITIVE + IDEMPOTENT. Preserves every existing column and all existing data.
-- Adds: new destination columns, scalable auto-generated destination_code + slug
-- + id, a normalized `gps_zones` table, `destination_id` foreign keys on related
-- content tables, count/status tracking, a dashboard view, indexes, and RLS.
-- Run in the Supabase SQL editor for project qqeyvhcgirmfokoftiuz. Safe to re-run.
-- ============================================================================

create extension if not exists pgcrypto;

-- ── New destination columns (all additive) ──────────────────────────────────
alter table public.destinations add column if not exists county text;
alter table public.destinations add column if not exists city text;
alter table public.destinations add column if not exists region text;
alter table public.destinations add column if not exists subcategory text;
alter table public.destinations add column if not exists gps_radius_ft integer default 1000;
alter table public.destinations add column if not exists email text;
alter table public.destinations add column if not exists facebook text;
alter table public.destinations add column if not exists instagram text;
alter table public.destinations add column if not exists youtube text;
alter table public.destinations add column if not exists ai_enabled boolean not null default true;
alter table public.destinations add column if not exists research_status text not null default 'pending';
alter table public.destinations add column if not exists story_status text not null default 'pending';
alter table public.destinations add column if not exists audio_status text not null default 'pending';
alter table public.destinations add column if not exists image_status text not null default 'pending';
alter table public.destinations add column if not exists video_status text not null default 'pending';
alter table public.destinations add column if not exists story_count integer not null default 0;
alter table public.destinations add column if not exists audio_count integer not null default 0;
alter table public.destinations add column if not exists image_count integer not null default 0;
alter table public.destinations add column if not exists play_count integer not null default 0;
alter table public.destinations add column if not exists priority integer not null default 0;
alter table public.destinations add column if not exists visitor_center boolean not null default false;
alter table public.destinations add column if not exists pet_friendly boolean not null default false;
alter table public.destinations add column if not exists accessibility text;
alter table public.destinations add column if not exists best_season text;
alter table public.destinations add column if not exists entrance_fee text;
alter table public.destinations add column if not exists reservation_required boolean not null default false;
alter table public.destinations add column if not exists last_ai_research timestamptz;
alter table public.destinations add column if not exists last_story_generation timestamptz;
alter table public.destinations add column if not exists last_audio_generation timestamptz;
alter table public.destinations add column if not exists metadata jsonb not null default '{}'::jsonb;

comment on column public.destinations.destination_code is 'Scalable code, e.g. FLNF0001 (state + type prefix + sequence). Auto-generated.';
comment on column public.destinations.research_status is 'pending | in_progress | complete';
comment on column public.destinations.metadata is 'Free-form JSON for type-specific attributes; keeps the core table lean.';

-- ── Helpers: slug, state abbreviation, scalable destination_code ─────────────
create or replace function public.slugify(txt text) returns text
  language sql immutable as $$
  select trim(both '-' from regexp_replace(lower(coalesce(txt,'')), '[^a-z0-9]+', '-', 'g'));
$$;

-- 2-letter USPS abbreviation for a state name (falls back to first 2 letters).
create or replace function public.state_abbrev(p_state text) returns text
  language sql immutable as $$
  select coalesce((
    select a from (values
      ('alabama','AL'),('alaska','AK'),('arizona','AZ'),('arkansas','AR'),
      ('california','CA'),('colorado','CO'),('connecticut','CT'),('delaware','DE'),
      ('florida','FL'),('georgia','GA'),('hawaii','HI'),('idaho','ID'),
      ('illinois','IL'),('indiana','IN'),('iowa','IA'),('kansas','KS'),
      ('kentucky','KY'),('louisiana','LA'),('maine','ME'),('maryland','MD'),
      ('massachusetts','MA'),('michigan','MI'),('minnesota','MN'),('mississippi','MS'),
      ('missouri','MO'),('montana','MT'),('nebraska','NE'),('nevada','NV'),
      ('new hampshire','NH'),('new jersey','NJ'),('new mexico','NM'),('new york','NY'),
      ('north carolina','NC'),('north dakota','ND'),('ohio','OH'),('oklahoma','OK'),
      ('oregon','OR'),('pennsylvania','PA'),('rhode island','RI'),('south carolina','SC'),
      ('south dakota','SD'),('tennessee','TN'),('texas','TX'),('utah','UT'),
      ('vermont','VT'),('virginia','VA'),('washington','WA'),('west virginia','WV'),
      ('wisconsin','WI'),('wyoming','WY'),('district of columbia','DC')
    ) as s(n,a) where s.n = lower(trim(coalesce(p_state,'')))
  ), upper(substr(regexp_replace(coalesce(p_state,'XX'), '[^a-zA-Z]', '', 'g') || 'XX', 1, 2)));
$$;

-- Short prefix for a destination type (drives the code family).
create or replace function public.destination_type_prefix(p_type text) returns text
  language sql immutable as $$
  select case lower(trim(coalesce(p_type,'')))
    when 'national park' then 'NP'
    when 'national forest' then 'NF'
    when 'state park' then 'SP'
    when 'state forest' then 'SF'
    when 'spring' then 'SPR'
    when 'springs' then 'SPR'
    when 'wildlife management area' then 'WMA'
    when 'scenic drive' then 'DRIVE'
    when 'historic site' then 'HIST'
    when 'historical site' then 'HIST'
    when 'museum' then 'MUS'
    when 'city' then 'CITY'
    when 'beach' then 'BEACH'
    when 'campground' then 'CG'
    when 'trailhead' then 'TH'
    when 'business' then 'BIZ'
    else 'DEST'
  end;
$$;

-- Next scalable code for a (state, type), e.g. FLNF0001, FLNF0002, …
create or replace function public.generate_destination_code(p_type text, p_state text)
  returns text language plpgsql as $$
declare
  base text := public.state_abbrev(p_state) || public.destination_type_prefix(p_type);
  n integer;
begin
  select coalesce(max(nullif(regexp_replace(destination_code, '^' || base, ''), '')::integer), 0) + 1
    into n
    from public.destinations
   where destination_code ~ ('^' || base || '[0-9]+$');
  return base || lpad(n::text, 4, '0');
end $$;

-- BEFORE INSERT: fill destination_id, slug, and destination_code when missing.
create or replace function public.destination_defaults() returns trigger
  language plpgsql as $$
begin
  if new.destination_id is null then new.destination_id := gen_random_uuid(); end if;
  if new.slug is null or new.slug = '' then new.slug := public.slugify(new.name); end if;
  if new.destination_code is null or new.destination_code = '' then
    new.destination_code := public.generate_destination_code(new.destination_type, new.state_province);
  end if;
  return new;
end $$;
drop trigger if exists trg_destination_defaults on public.destinations;
create trigger trg_destination_defaults before insert on public.destinations
  for each row execute function public.destination_defaults();

-- ── Normalized related table: gps_zones ──────────────────────────────────────
create table if not exists public.gps_zones (
  id uuid primary key default gen_random_uuid(),
  destination_id uuid references public.destinations(destination_id) on delete cascade,
  name text,
  latitude double precision,
  longitude double precision,
  radius_ft integer not null default 500,
  priority integer not null default 0,
  trigger_type text not null default 'arrival',      -- arrival|departure|approach|scenic_overlook|trail_marker|road_segment
  trigger_direction text,                            -- any|northbound|southbound|eastbound|westbound
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.gps_zones is 'GPS trigger zones per destination (arrival/departure/approach/scenic/trail/road).';
create index if not exists idx_gps_zones_destination on public.gps_zones (destination_id);
create index if not exists idx_gps_zones_geo on public.gps_zones (latitude, longitude);
drop trigger if exists trg_set_updated_at on public.gps_zones;
create trigger trg_set_updated_at before update on public.gps_zones
  for each row execute function public.set_updated_at();

-- ── Link every content table back to destinations via destination_id ─────────
-- Adds the column + index where missing and a best-effort FK (NOT VALID so
-- existing data is never blocked). Skips tables that don't exist.
do $$
declare
  t text;
  content_tables text[] := array[
    'stories','story_library','knowledge_base','knowledge_articles',
    'species','wildlife','plants','trees','birds',
    'trails','campgrounds','events','businesses','historical_events',
    'images','videos','media','narrations','map_locations','generation_jobs'];
begin
  foreach t in array content_tables loop
    if to_regclass('public.' || t) is not null then
      execute format('alter table public.%I add column if not exists destination_id uuid;', t);
      execute format('create index if not exists idx_%s_destination on public.%I (destination_id);', t, t);
      begin
        execute format(
          'alter table public.%I add constraint fk_%s_destination '
          'foreign key (destination_id) references public.destinations(destination_id) '
          'on delete set null not valid;', t, t);
      exception when others then null;  -- already exists / not applicable
      end;
    end if;
  end loop;
end $$;

-- ── Counts + status maintenance ──────────────────────────────────────────────
-- Recompute denormalized counts for one destination (cheap cached values).
create or replace function public.recalc_destination_counts(p_id uuid)
  returns void language plpgsql as $$
declare v_stories int := 0; v_audio int := 0; v_images int := 0;
begin
  if to_regclass('public.story_library') is not null then
    select count(*) into v_stories from public.story_library where destination_id = p_id;
    select count(*) into v_audio from public.story_library
      where destination_id = p_id and coalesce(audio_url,'') <> '';
  end if;
  if to_regclass('public.images') is not null then
    select count(*) into v_images from public.images where destination_id = p_id;
  end if;
  update public.destinations
     set story_count = v_stories, audio_count = v_audio, image_count = v_images,
         updated_at = now()
   where destination_id = p_id;
end $$;

create or replace function public.recalc_all_destination_counts()
  returns void language plpgsql as $$
declare r record;
begin
  for r in select destination_id from public.destinations loop
    perform public.recalc_destination_counts(r.destination_id);
  end loop;
end $$;

-- ── Dashboard view ───────────────────────────────────────────────────────────
create or replace view public.v_destination_dashboard as
  select
    d.destination_id, d.destination_code, d.name, d.slug, d.destination_type,
    d.subcategory, d.state_province, d.county, d.city, d.region,
    d.research_status, d.story_status, d.audio_status, d.image_status, d.video_status,
    (d.latitude is not null and d.longitude is not null) as gps_ready,
    d.published, d.featured, d.priority, d.ai_enabled,
    d.story_count, d.audio_count, d.image_count, d.play_count,
    d.last_ai_research, d.last_story_generation, d.last_audio_generation,
    d.created_at, d.updated_at
  from public.destinations d;

-- ── Indexes for filtering / lookups at scale ─────────────────────────────────
create unique index if not exists idx_destinations_code on public.destinations (destination_code);
create unique index if not exists idx_destinations_slug on public.destinations (slug);
create index if not exists idx_destinations_type on public.destinations (destination_type);
create index if not exists idx_destinations_county on public.destinations (county);
create index if not exists idx_destinations_region on public.destinations (region);
create index if not exists idx_destinations_state on public.destinations (state_province);
create index if not exists idx_destinations_published on public.destinations (published);
create index if not exists idx_destinations_research on public.destinations (research_status);
create index if not exists idx_destinations_audio on public.destinations (audio_status);
create index if not exists idx_destinations_priority on public.destinations (priority desc);

-- ── RLS: gps_zones (public read; open write to match the app's pattern) ───────
alter table public.gps_zones enable row level security;
drop policy if exists "read_gps_zones" on public.gps_zones;
create policy "read_gps_zones" on public.gps_zones for select to anon, authenticated using (true);
drop policy if exists "write_gps_zones" on public.gps_zones;
create policy "write_gps_zones" on public.gps_zones for insert to anon, authenticated with check (true);
drop policy if exists "update_gps_zones" on public.gps_zones;
create policy "update_gps_zones" on public.gps_zones for update to anon, authenticated using (true) with check (true);
drop policy if exists "delete_gps_zones" on public.gps_zones;
create policy "delete_gps_zones" on public.gps_zones for delete to anon, authenticated using (true);

-- ── Backfill: fill ONLY missing codes/slugs; preserve existing values ─────────
-- Existing codes (e.g. 'OCALA') are kept to avoid breaking any code-based
-- linkage such as map_locations.park_code. New destinations get scalable codes
-- automatically from trg_destination_defaults. To migrate a legacy code by hand:
--   update destinations set destination_code =
--     generate_destination_code(destination_type, state_province) where ...;
update public.destinations
   set destination_code = public.generate_destination_code(destination_type, state_province)
 where destination_code is null or destination_code = '';
update public.destinations
   set slug = public.slugify(name)
 where slug is null or slug = '';
select public.recalc_all_destination_counts();
