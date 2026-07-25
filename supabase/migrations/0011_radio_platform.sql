-- National Park Buddy Radio platform: related tables + storage write policies.
-- Run in the Supabase SQL editor for project qqeyvhcgirmfokoftiuz.
-- (songs + stories already exist; this adds the rest and the storage policies
-- so the signed-in admin can upload files.)

-- ── Content tables (public read, authenticated write) ──────────────────────
create table if not exists public.stations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  park_code text,
  tagline text,
  genre text,
  logo_url text,
  color text,
  is_active boolean not null default true,
  sort_order integer default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.wildlife_alerts (
  id uuid primary key default gen_random_uuid(),
  park_code text,
  species text,
  title text not null,
  message text,
  severity text default 'info',
  audio_url text,
  latitude double precision,
  longitude double precision,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.safety_messages (
  id uuid primary key default gen_random_uuid(),
  park_code text,
  type text,
  title text not null,
  message text,
  severity text default 'info',
  audio_url text,
  priority integer default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.radio_queue (
  id uuid primary key default gen_random_uuid(),
  station text,
  park_code text,
  item_type text not null,        -- song | story | wildlife | safety | narration
  item_id text,
  position integer default 0,
  created_at timestamptz not null default now()
);

-- ── User-scoped tables (each user manages their own rows) ───────────────────
create table if not exists public.favorites (
  id uuid primary key default gen_random_uuid(),
  user_id uuid default auth.uid(),
  item_type text not null,        -- song | station
  item_id text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.listening_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid default auth.uid(),
  item_type text not null,
  item_id text,
  park_code text,
  duration_seconds integer,
  played_at timestamptz not null default now()
);

create table if not exists public.user_station_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid default auth.uid(),
  station text,
  park_code text,
  volume numeric default 1.0,
  updated_at timestamptz not null default now()
);

-- ── RLS ─────────────────────────────────────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array['stations','wildlife_alerts','safety_messages','radio_queue'] loop
    execute format('alter table public.%I enable row level security;', t);
    execute format('drop policy if exists "read_%1$s" on public.%1$s;', t);
    execute format('create policy "read_%1$s" on public.%1$s for select to anon, authenticated using (true);', t);
    execute format('drop policy if exists "write_%1$s" on public.%1$s;', t);
    execute format('create policy "write_%1$s" on public.%1$s for all to authenticated using (true) with check (true);', t);
  end loop;
end $$;

-- User-scoped: read/write only own rows.
do $$
declare t text;
begin
  foreach t in array array['favorites','listening_history','user_station_preferences'] loop
    execute format('alter table public.%I enable row level security;', t);
    execute format('drop policy if exists "own_%1$s" on public.%1$s;', t);
    execute format('create policy "own_%1$s" on public.%1$s for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());', t);
  end loop;
end $$;

-- songs already exists; ensure authenticated can write it.
alter table public.songs enable row level security;
drop policy if exists "read_songs" on public.songs;
create policy "read_songs" on public.songs for select to anon, authenticated using (true);
drop policy if exists "write_songs" on public.songs;
create policy "write_songs" on public.songs for all to authenticated using (true) with check (true);

-- ── Storage: allow signed-in admins to upload to the platform buckets ───────
do $$
declare b text;
begin
  foreach b in array array['music','artwork','stories','voiceovers','images','videos','songs'] loop
    execute format('drop policy if exists "ins_%1$s" on storage.objects;', b);
    execute format($p$create policy "ins_%1$s" on storage.objects for insert to authenticated with check (bucket_id = %1$L);$p$, b);
    execute format('drop policy if exists "upd_%1$s" on storage.objects;', b);
    execute format($p$create policy "upd_%1$s" on storage.objects for update to authenticated using (bucket_id = %1$L);$p$, b);
    execute format('drop policy if exists "del_%1$s" on storage.objects;', b);
    execute format($p$create policy "del_%1$s" on storage.objects for delete to authenticated using (bucket_id = %1$L);$p$, b);
  end loop;
end $$;
