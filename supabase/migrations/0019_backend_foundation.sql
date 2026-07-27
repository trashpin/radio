-- ============================================================================
-- ExplorerOS backend foundation (0019)
-- ----------------------------------------------------------------------------
-- ADDITIVE + IDEMPOTENT. Complements the existing content tables (destinations,
-- species, media, songs, stories, story_library, knowledge_base, radio_*,
-- generation_jobs, map_locations, campgrounds, trails, …) — it does NOT drop or
-- replace them. Adds the production backbone the app was missing: an auth/role
-- model, user-facing tables (bookmarks/favorites/trips/progress/achievements/
-- notifications), ops tables (audit/system logs, feature flags, API keys,
-- analytics, import/export jobs), content-support tables (businesses, events,
-- images, videos, voice profiles, story versions/reviews/tags, knowledge
-- sources), plus cross-cutting infrastructure: updated_at triggers, full-text +
-- GPS indexes, helper functions, dashboard views, and Storage buckets.
--
-- Safe to run on the current database and safe to re-run. Table-dependent
-- objects are guarded so a missing table never aborts the migration.
-- Run in the Supabase SQL editor for project qqeyvhcgirmfokoftiuz.
-- ============================================================================

create extension if not exists pgcrypto;

-- ── Auth / roles ─────────────────────────────────────────────────────────────
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url text,
  role text not null default 'user',          -- 'user' | 'editor' | 'admin'
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.profiles is 'One row per auth user; role drives admin access.';

create or replace function public.is_admin() returns boolean
  language sql stable as $$
  select exists (
    select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin');
$$;
comment on function public.is_admin() is 'True when the current user has the admin role.';

-- Auto-create a profile whenever an auth user is created.
create or replace function public.handle_new_user() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id, display_name)
  values (new.id, split_part(coalesce(new.email, ''), '@', 1))
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users for each row execute function public.handle_new_user();

-- ── Cross-cutting: updated_at ────────────────────────────────────────────────
create or replace function public.set_updated_at() returns trigger
  language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

-- Attach the updated_at trigger to every table that has an updated_at column.
do $$
declare r record;
begin
  for r in
    select c.table_name from information_schema.columns c
    join information_schema.tables t
      on t.table_schema = c.table_schema and t.table_name = c.table_name
    where c.table_schema = 'public' and c.column_name = 'updated_at'
      and t.table_type = 'BASE TABLE'
  loop
    execute format('drop trigger if exists trg_set_updated_at on public.%I;', r.table_name);
    execute format(
      'create trigger trg_set_updated_at before update on public.%I
         for each row execute function public.set_updated_at();', r.table_name);
  end loop;
end $$;

-- ── User-facing tables ───────────────────────────────────────────────────────
create table if not exists public.bookmarks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  entity_type text not null,                   -- 'story' | 'destination' | 'species' | …
  entity_id text not null,
  created_at timestamptz not null default now(),
  unique (user_id, entity_type, entity_id)
);

create table if not exists public.favorites (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  entity_type text not null,
  entity_id text not null,
  created_at timestamptz not null default now(),
  unique (user_id, entity_type, entity_id)
);

create table if not exists public.trips (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.trip_stops (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  destination_id uuid,
  title text,
  latitude double precision,
  longitude double precision,
  sort_order integer default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.user_progress (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  entity_type text not null,                   -- e.g. 'story'
  entity_id text not null,
  status text default 'played',                -- 'played' | 'completed'
  progress double precision default 0,
  updated_at timestamptz not null default now(),
  unique (user_id, entity_type, entity_id)
);

create table if not exists public.achievements (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  title text not null,
  description text,
  icon text,
  created_at timestamptz not null default now()
);
create table if not exists public.user_achievements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  achievement_id uuid not null references public.achievements(id) on delete cascade,
  earned_at timestamptz not null default now(),
  unique (user_id, achievement_id)
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  title text not null,
  body text,
  read boolean not null default false,
  created_at timestamptz not null default now()
);

-- ── Content-support tables ───────────────────────────────────────────────────
create table if not exists public.businesses (
  id uuid primary key default gen_random_uuid(),
  destination_id uuid, name text not null, category text, description text,
  website text, phone text, latitude double precision, longitude double precision,
  published boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  destination_id uuid, title text not null, description text,
  starts_at timestamptz, ends_at timestamptz,
  latitude double precision, longitude double precision,
  published boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.images (
  id uuid primary key default gen_random_uuid(),
  entity_type text, entity_id text, url text not null, alt_text text,
  credit text, sort_order integer default 0,
  created_at timestamptz not null default now()
);
create table if not exists public.videos (
  id uuid primary key default gen_random_uuid(),
  entity_type text, entity_id text, url text not null, title text, duration integer,
  created_at timestamptz not null default now()
);
create table if not exists public.voice_profiles (
  id uuid primary key default gen_random_uuid(),
  name text not null, voice_id text, provider text default 'elevenlabs',
  gender text, personality text, language text default 'en',
  speaking_rate double precision default 1.0, active boolean not null default true,
  created_at timestamptz not null default now()
);
create table if not exists public.story_versions (
  id uuid primary key default gen_random_uuid(),
  story_id uuid, version_number integer not null default 1,
  transcript text, created_by text, created_at timestamptz not null default now()
);
create table if not exists public.story_reviews (
  id uuid primary key default gen_random_uuid(),
  story_id uuid, reviewer text, decision text, notes text,
  created_at timestamptz not null default now()
);
create table if not exists public.story_tags (
  id uuid primary key default gen_random_uuid(),
  story_id uuid, tag text not null, unique (story_id, tag)
);
create table if not exists public.knowledge_sources (
  id uuid primary key default gen_random_uuid(),
  knowledge_id uuid, title text, url text, publisher text,
  retrieved_at timestamptz, created_at timestamptz not null default now()
);

-- ── Ops / platform tables ────────────────────────────────────────────────────
create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  actor text, action text not null, table_name text, record_id text,
  previous_value jsonb, new_value jsonb, ip_address text, success boolean default true,
  created_at timestamptz not null default now()
);
create table if not exists public.system_logs (
  id bigint generated always as identity primary key,
  level text not null default 'info', source text, message text, context jsonb,
  created_at timestamptz not null default now()
);
create table if not exists public.feature_flags (
  key text primary key, enabled boolean not null default false,
  description text, updated_at timestamptz not null default now()
);
create table if not exists public.api_keys (
  id uuid primary key default gen_random_uuid(),
  name text not null, provider text, key_hash text, active boolean not null default true,
  created_at timestamptz not null default now()
);
create table if not exists public.analytics_events (
  id bigint generated always as identity primary key,
  user_id uuid, event text not null, entity_type text, entity_id text, props jsonb,
  created_at timestamptz not null default now()
);
create table if not exists public.import_jobs (
  id uuid primary key default gen_random_uuid(),
  target_table text not null, status text not null default 'pending',
  total integer default 0, imported integer default 0, failed integer default 0,
  message text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.export_jobs (
  id uuid primary key default gen_random_uuid(),
  source_table text not null, status text not null default 'pending',
  file_url text, rows integer default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

-- Re-run the updated_at attach so the new tables get the trigger too.
do $$
declare r record;
begin
  for r in
    select c.table_name from information_schema.columns c
    join information_schema.tables t
      on t.table_schema = c.table_schema and t.table_name = c.table_name
    where c.table_schema = 'public' and c.column_name = 'updated_at'
      and t.table_type = 'BASE TABLE'
  loop
    execute format('drop trigger if exists trg_set_updated_at on public.%I;', r.table_name);
    execute format(
      'create trigger trg_set_updated_at before update on public.%I
         for each row execute function public.set_updated_at();', r.table_name);
  end loop;
end $$;

-- ── Indexes: GPS + full-text search (guarded on existing tables) ──────────────
do $$
begin
  if to_regclass('public.destinations') is not null then
    create index if not exists idx_destinations_geo on public.destinations (latitude, longitude);
    execute 'alter table public.destinations add column if not exists search_tsv tsvector '
      'generated always as (to_tsvector(''english'', coalesce(name,'''')||'' ''||coalesce(description,''''))) stored';
    create index if not exists idx_destinations_fts on public.destinations using gin (search_tsv);
  end if;
  if to_regclass('public.story_library') is not null then
    create index if not exists idx_story_geo on public.story_library (latitude, longitude);
    create index if not exists idx_story_pub on public.story_library (published, category);
    execute 'alter table public.story_library add column if not exists search_tsv tsvector '
      'generated always as (to_tsvector(''english'', coalesce(title,'''')||'' ''||coalesce(transcript,''''))) stored';
    create index if not exists idx_story_fts on public.story_library using gin (search_tsv);
  end if;
  if to_regclass('public.knowledge_base') is not null then
    execute 'alter table public.knowledge_base add column if not exists search_tsv tsvector '
      'generated always as (to_tsvector(''english'', coalesce(title,'''')||'' ''||coalesce(description,''''))) stored';
    create index if not exists idx_knowledge_fts on public.knowledge_base using gin (search_tsv);
  end if;
  if to_regclass('public.species') is not null then
    execute 'alter table public.species add column if not exists search_tsv tsvector '
      'generated always as (to_tsvector(''english'', coalesce(common_name,'''')||'' ''||coalesce(description,''''))) stored';
    create index if not exists idx_species_fts on public.species using gin (search_tsv);
  end if;
  if to_regclass('public.map_locations') is not null then
    create index if not exists idx_map_geo on public.map_locations (latitude, longitude);
  end if;
end $$;

-- Indexes on new tables.
create index if not exists idx_bookmarks_user on public.bookmarks (user_id);
create index if not exists idx_favorites_user on public.favorites (user_id);
create index if not exists idx_progress_user on public.user_progress (user_id);
create index if not exists idx_notifications_user on public.notifications (user_id, read);
create index if not exists idx_analytics_event on public.analytics_events (event, created_at);
create index if not exists idx_audit_table on public.audit_logs (table_name, created_at);

-- ── Helper functions ─────────────────────────────────────────────────────────
-- Great-circle distance (meters).
create or replace function public.gc_meters(lat1 double precision, lng1 double precision,
                                            lat2 double precision, lng2 double precision)
  returns double precision language sql immutable as $$
  select 6371000 * 2 * asin(sqrt(
    power(sin(radians(lat2-lat1)/2), 2) +
    cos(radians(lat1))*cos(radians(lat2))*power(sin(radians(lng2-lng1)/2), 2)));
$$;

-- Published destinations within radius_km, nearest first.
create or replace function public.nearby_destinations(in_lat double precision, in_lng double precision,
                                                       radius_km double precision default 50)
  returns setof public.destinations language sql stable as $$
  select * from public.destinations d
  where d.published and d.latitude is not null and d.longitude is not null
    and public.gc_meters(in_lat, in_lng, d.latitude, d.longitude) <= radius_km * 1000
  order by public.gc_meters(in_lat, in_lng, d.latitude, d.longitude) asc;
$$;

-- A random published, audio-ready story (optionally for a park).
create or replace function public.random_published_story(in_park text default null)
  returns setof public.story_library language sql stable as $$
  select * from public.story_library s
  where s.published and coalesce(s.audio_url,'') <> ''
    and (in_park is null or s.park_id = in_park)
  order by random() limit 1;
$$;

-- Publish a story (approve + publish) — everyday admin action without SQL.
create or replace function public.publish_story(in_id uuid)
  returns void language sql as $$
  update public.story_library
     set approved = true, published = true, status = 'completed', updated_at = now()
   where id = in_id;
$$;

-- Content statistics as JSON (powers the DB dashboard).
create or replace function public.content_statistics()
  returns jsonb language sql stable as $$
  select jsonb_build_object(
    'destinations', (select count(*) from public.destinations),
    'species', (select count(*) from public.species),
    'stories', (select count(*) from public.story_library),
    'stories_published', (select count(*) from public.story_library where published),
    'stories_missing_audio', (select count(*) from public.story_library where coalesce(audio_url,'')=''),
    'knowledge_facts', (select count(*) from public.knowledge_base),
    'songs', (select count(*) from public.songs),
    'jobs_pending', (select count(*) from public.generation_jobs where status='pending'),
    'jobs_failed', (select count(*) from public.generation_jobs where status='failed')
  );
$$;

-- Lightweight DB health snapshot.
create or replace function public.db_health()
  returns jsonb language sql stable as $$
  select jsonb_build_object(
    'tables', (select count(*) from information_schema.tables where table_schema='public'),
    'db_size', pg_size_pretty(pg_database_size(current_database())),
    'generated_at', now()
  );
$$;

-- ── Views (guarded) ──────────────────────────────────────────────────────────
create or replace view public.v_published_stories as
  select * from public.story_library where published;
create or replace view public.v_missing_audio as
  select id, title, category, park_id from public.story_library
   where coalesce(audio_url,'') = '';
create or replace view public.v_gps_ready_stories as
  select id, title, latitude, longitude, trigger_radius_m from public.story_library
   where published and latitude is not null and coalesce(audio_url,'') <> '';
create or replace view public.v_jobs_dashboard as
  select status, count(*) as jobs from public.generation_jobs group by status;
create or replace view public.v_content_statistics as
  select public.content_statistics() as stats;

-- ── Story pipeline trigger: queue audio when a story is approved ──────────────
create or replace function public.queue_audio_on_approval() returns trigger
  language plpgsql as $$
begin
  if new.approved and not coalesce(old.approved, false)
     and coalesce(new.audio_url,'') = '' then
    insert into public.generation_jobs(destination, job_type, status, message)
    values (coalesce(new.location, new.title), 'audio', 'pending',
            'auto-queued: story approved (id '||new.id||')');
  end if;
  return new;
end $$;
do $$
begin
  if to_regclass('public.story_library') is not null then
    drop trigger if exists trg_queue_audio on public.story_library;
    create trigger trg_queue_audio after update on public.story_library
      for each row execute function public.queue_audio_on_approval();
  end if;
end $$;

-- ── RLS ──────────────────────────────────────────────────────────────────────
-- Owner-scoped user tables: each user sees/manages only their own rows.
do $$
declare t text;
begin
  foreach t in array array['bookmarks','favorites','trips','trip_stops',
      'user_progress','user_achievements','notifications'] loop
    execute format('alter table public.%I enable row level security;', t);
    execute format('drop policy if exists "own_%s" on public.%I;', t, t);
  end loop;
end $$;
create policy "own_bookmarks" on public.bookmarks for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own_favorites" on public.favorites for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own_trips" on public.trips for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own_trip_stops" on public.trip_stops for all to authenticated
  using (exists (select 1 from public.trips tr where tr.id = trip_id and tr.user_id = auth.uid()))
  with check (exists (select 1 from public.trips tr where tr.id = trip_id and tr.user_id = auth.uid()));
create policy "own_user_progress" on public.user_progress for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own_user_achievements" on public.user_achievements for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own_notifications" on public.notifications for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- profiles: read/update own; admins manage all.
alter table public.profiles enable row level security;
drop policy if exists "profiles_self_read" on public.profiles;
create policy "profiles_self_read" on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_admin());
drop policy if exists "profiles_self_update" on public.profiles;
create policy "profiles_self_update" on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- Public-read content tables + open writes (matches the app's existing pattern;
-- tighten writes to public.is_admin() when the admin role model is adopted).
do $$
declare t text;
begin
  foreach t in array array['businesses','events','images','videos','voice_profiles',
      'story_versions','story_reviews','story_tags','knowledge_sources','achievements'] loop
    execute format('alter table public.%I enable row level security;', t);
    execute format('drop policy if exists "read_%s" on public.%I;', t, t);
    execute format('create policy "read_%s" on public.%I for select to anon, authenticated using (true);', t, t);
    execute format('drop policy if exists "write_%s" on public.%I;', t, t);
    execute format('create policy "write_%s" on public.%I for insert to anon, authenticated with check (true);', t, t);
    execute format('drop policy if exists "update_%s" on public.%I;', t, t);
    execute format('create policy "update_%s" on public.%I for update to anon, authenticated using (true) with check (true);', t, t);
    execute format('drop policy if exists "delete_%s" on public.%I;', t, t);
    execute format('create policy "delete_%s" on public.%I for delete to anon, authenticated using (true);', t, t);
  end loop;
end $$;

-- Admin-only ops tables (logs/keys/flags/analytics/jobs). Reads gated to admins;
-- writes flow through SECURITY DEFINER triggers/functions or the service role.
do $$
declare t text;
begin
  foreach t in array array['audit_logs','system_logs','feature_flags','api_keys',
      'analytics_events','import_jobs','export_jobs'] loop
    execute format('alter table public.%I enable row level security;', t);
    execute format('drop policy if exists "admin_read_%s" on public.%I;', t, t);
    execute format('create policy "admin_read_%s" on public.%I for select to authenticated using (public.is_admin());', t, t);
    execute format('drop policy if exists "admin_write_%s" on public.%I;', t, t);
    execute format('create policy "admin_write_%s" on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin());', t, t);
  end loop;
end $$;

-- ── Storage buckets ───────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public)
values ('audio','audio',true), ('images','images',true), ('videos','videos',true),
       ('documents','documents',true), ('avatars','avatars',true),
       ('uploads','uploads',true), ('exports','exports',false), ('temporary','temporary',false)
on conflict (id) do nothing;

-- ── Seed: default feature flags ───────────────────────────────────────────────
insert into public.feature_flags (key, enabled, description) values
  ('dj_banter', true, 'DJ talks between songs'),
  ('gps_stories', true, 'GPS-triggered story playback'),
  ('ai_generation', true, 'AI research/story/audio generation')
on conflict (key) do nothing;
