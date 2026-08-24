-- Marion County Adventures — Phase 1 core data model.
--
-- Reuses existing infrastructure rather than duplicating it:
--   * Positioning/arrival detection uses the SAME GeoMath utility and the
--     SAME live GPS position stream (gpsControllerProvider) every other
--     location-aware feature already uses -- NOT a second GPS system.
--   * A stop MAY optionally link to an existing `locations` row (for reuse
--     of a location's existing photos/description, and so the same physical
--     place can eventually be shared across missions), but is otherwise
--     self-contained with its own lat/lng/radius so a mission-only POI
--     doesn't require first creating a general-purpose `locations` row.
--   * Deliberately does NOT route mission arrival through the general
--     `geofences`/`get_nearby_geofences` hierarchy -- that system serves a
--     different concern (location-aware radio's park/county/POI priority
--     arbitration) and mixing mission-specific arrival logic into it risks
--     unintended interaction between two unrelated features.
--   * Narration audio reuses the existing discover-narration edge function
--     (ElevenLabs + a shared cache table) -- see that function's new
--     subjectType 'mission'.
--
-- TRAVEL STORY and APPROACH STORY (spec Phase 2/3) are the same underlying
-- primitive -- "at distance X from the target stop, play narration Y" -- so
-- they share one table (`mission_travel_stories`) distinguished by
-- `trigger_type`, rather than three near-identical tables.

create table if not exists public.missions (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  category text,                       -- free text, e.g. 'history','mystery','nature' -- matches
                                        -- this app's existing free-text category convention
  difficulty text check (difficulty is null or difficulty in ('easy','moderate','hard')),
  estimated_duration_minutes integer,
  published boolean not null default false,
  starting_location_id uuid references public.locations(id),
  opening_narration_text text,
  opening_narration_audio_url text,
  completion_reward_xp integer not null default 0,
  completion_badge text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.mission_stops (
  id uuid primary key default gen_random_uuid(),
  mission_id uuid not null references public.missions(id) on delete cascade,
  sequence integer not null,
  title text not null,
  location_id uuid references public.locations(id),   -- optional reuse of an existing location
  latitude double precision not null,
  longitude double precision not null,
  arrival_radius_meters double precision not null default 150,  -- ~500 ft
  arrival_narration_text text,
  arrival_narration_audio_url text,
  requires_qr boolean not null default true,
  qr_portal_id uuid,            -- FK added below, after qr_portals exists
  old_world_id uuid,            -- FK added below, after old_worlds exists
  next_stop_id uuid references public.mission_stops(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (mission_id, sequence)
);

create table if not exists public.mission_travel_stories (
  id uuid primary key default gen_random_uuid(),
  mission_id uuid not null references public.missions(id) on delete cascade,
  stop_id uuid not null references public.mission_stops(id) on delete cascade,
  -- 'travel' (informational, further out) | 'approach' (anticipation-building,
  -- close in) -- free text so an admin/future mission type can introduce a
  -- new beat without a migration.
  trigger_type text not null default 'travel',
  trigger_distance_meters double precision not null,
  text text not null,
  audio_url text,
  priority integer not null default 0,
  play_once boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.old_worlds (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  historical_period text,
  -- Defaults to true deliberately: content must be explicitly marked
  -- verified-historical by an admin, never accidentally presented as real.
  is_fictional boolean not null default true,
  narration_text text,
  narration_audio_url text,
  hero_image_url text,
  historical_map_image_url text,
  narrator_name text,
  characters jsonb not null default '[]',
  clue_text text,
  next_stop_id uuid references public.mission_stops(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.qr_portals (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  mission_stop_id uuid references public.mission_stops(id) on delete set null,
  old_world_id uuid references public.old_worlds(id) on delete set null,
  -- true: resolved against whatever mission/stop the scanning player
  -- currently has active, rather than a hardcoded mission_stop_id -- the
  -- "same physical QR marker reusable across multiple missions" case.
  is_global boolean not null default false,
  requires_gps_proximity boolean not null default true,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.mission_stops
  add constraint mission_stops_qr_portal_fk foreign key (qr_portal_id) references public.qr_portals(id),
  add constraint mission_stops_old_world_fk foreign key (old_world_id) references public.old_worlds(id);

create table if not exists public.mission_progress (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  mission_id uuid not null references public.missions(id) on delete cascade,
  current_stop_id uuid references public.mission_stops(id),
  completed_stop_ids uuid[] not null default '{}',
  discovered_location_ids uuid[] not null default '{}',
  unlocked_old_world_ids uuid[] not null default '{}',
  fired_content_ids uuid[] not null default '{}',
  xp integer not null default 0,
  status text not null default 'not_started'
    check (status in ('not_started','in_progress','completed','abandoned')),
  started_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (user_id, mission_id)
);

create index if not exists mission_stops_mission_idx on public.mission_stops(mission_id);
create index if not exists mission_travel_stories_stop_idx on public.mission_travel_stories(stop_id);
create index if not exists qr_portals_code_idx on public.qr_portals(code);
create index if not exists mission_progress_user_idx on public.mission_progress(user_id);

alter table public.missions enable row level security;
alter table public.mission_stops enable row level security;
alter table public.mission_travel_stories enable row level security;
alter table public.old_worlds enable row level security;
alter table public.qr_portals enable row level security;
alter table public.mission_progress enable row level security;

do $$
begin
  -- Content tables: readable by anyone (matches events/locations/categories
  -- convention); writes require authenticated (matches event_sources/
  -- discovered_events -- a notch stricter than categories' anon-write,
  -- since mission content is game design, not visitor-submitted data). No
  -- is_admin() role function exists in this project (confirmed during the
  -- audit) -- admin screens are gated client-side, same as every other
  -- admin module in this app.
  execute 'create policy "missions_read" on public.missions for select to anon, authenticated using (true)';
  execute 'create policy "missions_write" on public.missions for all to authenticated using (true) with check (true)';

  execute 'create policy "mission_stops_read" on public.mission_stops for select to anon, authenticated using (true)';
  execute 'create policy "mission_stops_write" on public.mission_stops for all to authenticated using (true) with check (true)';

  execute 'create policy "mission_travel_stories_read" on public.mission_travel_stories for select to anon, authenticated using (true)';
  execute 'create policy "mission_travel_stories_write" on public.mission_travel_stories for all to authenticated using (true) with check (true)';

  execute 'create policy "old_worlds_read" on public.old_worlds for select to anon, authenticated using (true)';
  execute 'create policy "old_worlds_write" on public.old_worlds for all to authenticated using (true) with check (true)';

  execute 'create policy "qr_portals_read" on public.qr_portals for select to anon, authenticated using (true)';
  execute 'create policy "qr_portals_write" on public.qr_portals for all to authenticated using (true) with check (true)';

  -- Player progress is personal data: self-only, matching event_matches_self_read.
  execute 'create policy "mission_progress_self_all" on public.mission_progress for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id)';
end $$;
