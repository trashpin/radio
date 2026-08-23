-- Discover Marion County — personalized discovery experience replacing the
-- Radio tab's primary nav slot. Purely additive: extends `events`/`profiles`
-- with nullable columns, adds two small new support tables. Nothing existing
-- is removed, renamed, or made non-nullable.

alter table public.events
  add column if not exists category           text,
  add column if not exists interest_tags      text[] default '{}',
  add column if not exists cost_info          text,
  add column if not exists registration_url   text,
  add column if not exists ticket_url         text,
  add column if not exists phone              text,
  add column if not exists accessibility_info text,
  add column if not exists family_friendly    boolean;

alter table public.profiles
  add column if not exists interests text[] not null default '{}';

-- Cached AI-narrated Discover audio ("Hear About It" / "Tell Me More"
-- segments) — generate once, reuse; keyed by the source item so the same
-- item is never re-synthesized on every tap.
create table if not exists public.discover_narrations (
  id           uuid primary key default gen_random_uuid(),
  subject_type text not null, -- 'event' | 'gem' | 'location'
  subject_id   text not null,
  kind         text not null, -- 'short' (Hear About It) | 'long' (Tell Me More)
  script       text not null,
  audio_url    text,
  created_at   timestamptz not null default now(),
  unique (subject_type, subject_id, kind)
);

alter table public.discover_narrations enable row level security;
do $$
begin
  execute 'drop policy if exists "discover_narrations_read" on public.discover_narrations';
  execute 'create policy "discover_narrations_read" on public.discover_narrations for select to anon, authenticated using (true)';
  execute 'drop policy if exists "discover_narrations_write" on public.discover_narrations';
  execute 'create policy "discover_narrations_write" on public.discover_narrations for insert to anon, authenticated with check (true)';
  execute 'drop policy if exists "discover_narrations_update" on public.discover_narrations';
  execute 'create policy "discover_narrations_update" on public.discover_narrations for update to anon, authenticated using (true) with check (true)';
end $$;

-- Behavioral-personalization architecture hook — logged at natural
-- interaction points (opened/saved/heard/navigated/tickets/website) starting
-- now, but deliberately NOT read by the v1 recommendation scorer yet. This is
-- the seam a later phase plugs into rather than a schema change at that time.
create table if not exists public.discover_interactions (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid references auth.users(id) on delete cascade,
  item_type        text not null,
  item_id          text not null,
  interaction_type text not null,
  created_at       timestamptz not null default now()
);
create index if not exists discover_interactions_user_idx
  on public.discover_interactions (user_id, created_at desc);

alter table public.discover_interactions enable row level security;
do $$
begin
  execute 'drop policy if exists "discover_interactions_insert" on public.discover_interactions';
  execute 'create policy "discover_interactions_insert" on public.discover_interactions for insert to anon, authenticated with check (user_id is null or auth.uid() = user_id)';
  execute 'drop policy if exists "discover_interactions_read_own" on public.discover_interactions';
  execute 'create policy "discover_interactions_read_own" on public.discover_interactions for select to authenticated using (auth.uid() = user_id)';
end $$;
