-- ExplorerOS — Master Location database (one location engine for everything)
--
-- A single canonical `locations` table that Map, Explorer Radio, GPS triggers,
-- "I See Something", Nearby Explorer, Narration, Search, and Routes all read.
-- Existing place sources (map_locations, destinations) are migrated in with
-- their original id preserved in (source, source_id) so relationships hold and
-- re-runs are idempotent. Location Content narration attaches to these master
-- locations (via narration_ids) rather than storing its own places.

create extension if not exists "pgcrypto";

create table if not exists public.locations (
  id                    uuid primary key default gen_random_uuid(),

  name                  text not null default '',
  category              text not null default 'point_of_interest', -- LocationType id
  latitude              double precision,
  longitude             double precision,

  county                text,
  city                  text,
  community             text,
  address               text,
  description           text,

  trigger_radius        double precision, -- meters; GPS "entered" radius
  map_visibility_radius double precision, -- meters; show on map within this
  priority              integer not null default 0,

  narration_ids         text[]  default '{}',
  audio_files           text[]  default '{}',
  images                text[]  default '{}',
  videos                text[]  default '{}',
  related_locations     text[]  default '{}',

  active                boolean not null default true,
  featured              boolean not null default false,
  hidden                boolean not null default false,

  -- Provenance (for the one-time migration + idempotency).
  source                text,   -- 'map_locations' | 'destinations' | 'manual' | …
  source_id             text,
  destination_code      text,

  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create unique index if not exists locations_source_uidx
  on public.locations (source, source_id) where source is not null;
create index if not exists locations_geo_idx on public.locations (latitude, longitude);
create index if not exists locations_category_idx on public.locations (category);
create index if not exists locations_county_idx on public.locations (county);
create index if not exists locations_active_idx on public.locations (active);

create or replace function public.locations_touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

drop trigger if exists locations_set_updated_at on public.locations;
create trigger locations_set_updated_at
  before update on public.locations
  for each row execute function public.locations_touch_updated_at();

-- Records a play (GPS/radio) for cooldown tracking.
create or replace function public.location_record_play(p_id uuid)
returns void language plpgsql as $$
begin
  update public.locations set updated_at = now() where id = p_id;
end $$;

-- ── Data migration ─────────────────────────────────────────────────────────
-- Normalize a free-form source category into a master LocationType id.
create or replace function public.map_location_type(raw text, nm text)
returns text language plpgsql immutable as $$
declare t text := lower(coalesce(raw, '') || ' ' || coalesce(nm, ''));
begin
  if t ~ 'county' then return 'county';
  elsif t ~ 'community|unincorporated' then return 'community';
  elsif t ~ 'city|town' then return 'city';
  elsif t ~ 'spring' then return 'spring';
  elsif t ~ 'river|creek' then return 'river';
  elsif t ~ 'lake|pond|reservoir' then return 'lake';
  elsif t ~ 'national forest|forest' then return 'forest';
  elsif t ~ 'national park' then return 'national_park';
  elsif t ~ 'state park' then return 'state_park';
  elsif t ~ 'county park' then return 'county_park';
  elsif t ~ 'historic district' then return 'historic_district';
  elsif t ~ 'histor|fort|heritage|monument' then return 'historic_site';
  elsif t ~ 'scenic road|byway|scenic drive|highway' then return 'scenic_road';
  elsif t ~ 'trailhead' then return 'trailhead';
  elsif t ~ 'trail' then return 'trail';
  elsif t ~ 'camp' then return 'campground';
  elsif t ~ 'boat ramp|boat|ramp' then return 'boat_ramp';
  elsif t ~ 'visitor' then return 'visitor_center';
  elsif t ~ 'wildlife' then return 'wildlife_viewing';
  elsif t ~ 'overlook|scenic|vista' then return 'scenic_overlook';
  elsif t ~ 'museum' then return 'museum';
  elsif t ~ 'restaurant|food|dining' then return 'restaurant';
  elsif t ~ 'gas|fuel' then return 'gas_station';
  elsif t ~ 'parking' then return 'parking';
  elsif t ~ 'safety|alert|warning' then return 'safety_alert';
  elsif t ~ 'hidden|gem' then return 'hidden_gem';
  elsif t ~ 'attraction' then return 'attraction';
  else return 'point_of_interest';
  end if;
end $$;

do $$
begin
  -- map_locations → master
  if to_regclass('public.map_locations') is not null then
    insert into public.locations
      (name, category, latitude, longitude, description, trigger_radius,
       images, audio_files, destination_code, source, source_id, active)
    select
      coalesce(nullif(trim(m.name), ''), 'Unnamed'),
      public.map_location_type(m.category, m.name),
      m.latitude, m.longitude, m.description, m.trigger_radius_m,
      case when m.image_url is not null then array[m.image_url] else '{}' end,
      case when m.audio_url is not null then array[m.audio_url] else '{}' end,
      m.park_code, 'map_locations', m.id::text, true
    from public.map_locations m
    where m.latitude is not null and m.longitude is not null
      and not (m.latitude = 0 and m.longitude = 0)
    on conflict (source, source_id) where source is not null do nothing;
  end if;

  -- destinations → master
  if to_regclass('public.destinations') is not null then
    insert into public.locations
      (name, category, latitude, longitude, county, city, description,
       images, destination_code, featured, source, source_id, active)
    select
      coalesce(nullif(trim(d.name), ''), 'Unnamed'),
      public.map_location_type(
        coalesce(d.destination_type, d.category, ''), d.name),
      d.latitude, d.longitude,
      d.county, d.city, d.description,
      case when d.hero_image is not null then array[d.hero_image]
           when d.image_url is not null then array[d.image_url] else '{}' end,
      coalesce(d.destination_code, d.destination_id::text),
      coalesce(d.featured, false),
      'destinations', d.destination_id::text, true
    from public.destinations d
    where d.latitude is not null and d.longitude is not null
      and not (d.latitude = 0 and d.longitude = 0)
    on conflict (source, source_id) where source is not null do nothing;
  end if;
exception when others then
  raise notice 'locations backfill skipped a source: %', sqlerrm;
end $$;

-- RLS: public read; admin (anon/authenticated) write (mirrors other tables).
alter table public.locations enable row level security;
do $$
begin
  execute 'drop policy if exists "locations_read" on public.locations';
  execute 'create policy "locations_read" on public.locations for select to anon, authenticated using (true)';
  execute 'drop policy if exists "locations_write" on public.locations';
  execute 'create policy "locations_write" on public.locations for insert to anon, authenticated with check (true)';
  execute 'drop policy if exists "locations_update" on public.locations';
  execute 'create policy "locations_update" on public.locations for update to anon, authenticated using (true) with check (true)';
  execute 'drop policy if exists "locations_delete" on public.locations';
  execute 'create policy "locations_delete" on public.locations for delete to anon, authenticated using (true)';
end $$;
