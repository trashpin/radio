-- ============================================================================
-- ExplorerOS AI Narration Studio (0022)
-- ----------------------------------------------------------------------------
-- Per-destination, multi-script AI narration (25 script types + variations) and
-- destination-to-destination route narration, with quality-control metrics and
-- an approval → publish lifecycle. Designed to scale to 100k+ destinations and
-- millions of narration assets.
--
-- ADDITIVE + IDEMPOTENT. Run in the Supabase SQL editor for project
-- qqeyvhcgirmfokoftiuz. Safe to run and re-run.
-- ============================================================================

create extension if not exists pgcrypto;

-- ── destination_narrations ───────────────────────────────────────────────────
create table if not exists public.destination_narrations (
  id uuid primary key default gen_random_uuid(),
  destination_id uuid,                 -- FK added best-effort below
  script_type text not null,           -- arrival | main_history | wildlife | …
  title text,
  script text,
  audio_url text,
  voice text,
  duration_seconds integer,
  status text not null default 'draft',-- draft|review|approved|published|needs_review
  version integer not null default 1,
  variant integer not null default 1,  -- for x3/x5 variations per type
  language text not null default 'en',
  season text,                         -- any|spring|summer|fall|winter
  time_of_day text,                    -- any|sunrise|day|sunset|night
  -- quality control
  word_count integer not null default 0,
  speaking_seconds integer not null default 0,   -- @150 wpm
  readability_score double precision,
  fact_confidence double precision,    -- 0..1 (how grounded in known facts)
  duplicate_score double precision,    -- 0..1 (similarity to siblings)
  needs_review boolean not null default false,   -- true when facts were missing
  -- provenance
  ai_model text,
  prompt_used text,
  approved_by text,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.destination_narrations is
  'AI narration scripts + audio per destination (25 script types, with variants), QC-scored, with an approval/publish lifecycle. Explorer Radio picks a random published variant.';
comment on column public.destination_narrations.needs_review is
  'Set when the generator lacked verified facts and emitted a placeholder for admin review.';

create index if not exists idx_dn_destination on public.destination_narrations (destination_id);
create index if not exists idx_dn_type on public.destination_narrations (destination_id, script_type, status);
create index if not exists idx_dn_status on public.destination_narrations (status);
create index if not exists idx_dn_published on public.destination_narrations (destination_id, script_type)
  where status = 'published';
create index if not exists idx_dn_lang on public.destination_narrations (language);

-- ── route_narrations ─────────────────────────────────────────────────────────
create table if not exists public.route_narrations (
  id uuid primary key default gen_random_uuid(),
  from_destination_id uuid,
  to_destination_id uuid,
  route_name text,
  distance double precision,           -- miles
  estimated_drive_time integer,        -- minutes
  script text,
  audio_url text,
  voice text,
  duration_seconds integer,
  word_count integer not null default 0,
  status text not null default 'draft',
  language text not null default 'en',
  ai_model text,
  needs_review boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (from_destination_id, to_destination_id, language)
);
comment on table public.route_narrations is
  'Driving narration between two destinations (history/scenery/wildlife/towns), played by Explorer Radio en route.';
create index if not exists idx_rn_from on public.route_narrations (from_destination_id);
create index if not exists idx_rn_to on public.route_narrations (to_destination_id);

-- ── updated_at triggers (reuse set_updated_at from 0019 if present) ───────────
do $$
begin
  if to_regprocedure('public.set_updated_at()') is not null then
    drop trigger if exists trg_set_updated_at on public.destination_narrations;
    create trigger trg_set_updated_at before update on public.destination_narrations
      for each row execute function public.set_updated_at();
    drop trigger if exists trg_set_updated_at on public.route_narrations;
    create trigger trg_set_updated_at before update on public.route_narrations
      for each row execute function public.set_updated_at();
  end if;
end $$;

-- Best-effort FKs to destinations (NOT VALID so existing data is never blocked).
do $$
begin
  if to_regclass('public.destinations') is not null then
    begin
      execute 'alter table public.destination_narrations add constraint fk_dn_destination '
        'foreign key (destination_id) references public.destinations(destination_id) '
        'on delete cascade not valid';
    exception when others then null; end;
    begin
      execute 'alter table public.route_narrations add constraint fk_rn_from '
        'foreign key (from_destination_id) references public.destinations(destination_id) '
        'on delete cascade not valid';
    exception when others then null; end;
    begin
      execute 'alter table public.route_narrations add constraint fk_rn_to '
        'foreign key (to_destination_id) references public.destinations(destination_id) '
        'on delete cascade not valid';
    exception when others then null; end;
  end if;
end $$;

-- ── Coverage view (powers the studio header + jobs dashboard) ─────────────────
create or replace view public.v_destination_narration_coverage as
  select
    destination_id,
    count(*) as scripts,
    count(*) filter (where coalesce(audio_url,'') <> '') as audio_files,
    count(*) filter (where status = 'approved') as approved,
    count(*) filter (where status = 'published') as published,
    count(*) filter (where needs_review) as needs_review,
    count(distinct script_type) as script_types,
    max(updated_at) as last_updated,
    max(created_at) as last_generated
  from public.destination_narrations
  group by destination_id;

-- ── Random published narration for a (destination, script type) ──────────────
-- Explorer Radio uses this to vary which script variant it plays.
create or replace function public.random_narration(p_destination uuid, p_type text,
                                                    p_lang text default 'en')
  returns setof public.destination_narrations language sql stable as $$
  select * from public.destination_narrations
   where destination_id = p_destination and script_type = p_type
     and status = 'published' and language = p_lang
     and coalesce(audio_url,'') <> ''
   order by random() limit 1;
$$;

-- ── RLS: public read; open write to match the app's admin-write pattern ───────
do $$
declare t text;
begin
  foreach t in array array['destination_narrations','route_narrations'] loop
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
