-- Content Generator: the master content engine. Research produces categorized
-- facts (knowledge_base); a background job queue (generation_jobs) drives
-- research → knowledge → stories → audio → review → publish. Stories themselves
-- live in story_library (migration 0017).
-- Run in the Supabase SQL editor for project qqeyvhcgirmfokoftiuz. Idempotent.

create table if not exists public.knowledge_base (
  id uuid primary key default gen_random_uuid(),
  destination text not null,
  destination_category text,          -- national_park/state_forest/spring/...
  category text not null,             -- History/Wildlife/Geology/...
  title text not null,
  description text,
  source text,
  latitude double precision,
  longitude double precision,
  confidence_score double precision default 0.7,
  verified boolean not null default false,
  approved boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists knowledge_base_lookup_idx
  on public.knowledge_base (destination, category, approved);

create table if not exists public.generation_jobs (
  id uuid primary key default gen_random_uuid(),
  destination text not null,
  destination_category text,
  state text,
  county text,
  latitude double precision,
  longitude double precision,
  radius_m integer default 150,
  job_type text not null default 'research',   -- research/knowledge/stories/audio/full/bulk
  status text not null default 'pending',       -- pending/researching/building_knowledge/generating_stories/generating_audio/waiting_for_review/completed/failed
  progress integer not null default 0,
  message text,
  notes text,
  website text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists generation_jobs_status_idx
  on public.generation_jobs (status, created_at);

do $$
declare t text;
begin
  foreach t in array array['knowledge_base','generation_jobs'] loop
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
