-- Personalized voiced event alerts + push notifications architecture.
-- Approved Event -> Match Against User -> Personalized Audio -> Deep Link
-- -> Push Notification -> (test mode first) -> Open Event -> Hear About It.
--
-- Purely additive. Reuses existing events/profiles/interests -- no
-- duplicate user-preference or event-content system. Notification
-- PREFERENCES live in the existing profiles.settings jsonb (already a
-- free-form column) rather than a new table, since they're a handful of
-- booleans/an enum, not relational data.

-- One row per (event, user) match this engine has ever considered --
-- the repeat-protection ledger (spec: "do not send the same event
-- repeatedly to the same user") and the admin monitoring source of truth
-- (spec: "Event / Potential matches / High-match users / Notifications
-- generated/sent/opened / Audio generated/played").
create table if not exists public.event_matches (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  match_tier text not null check (match_tier in ('high','medium','low')),
  score numeric not null,
  matched_interest_tags text[] not null default '{}',
  distance_meters double precision,
  -- 'matched' (scored only) -> 'notified' (push sent) -> 'opened' (tapped) ->
  -- 'audio_played' (heard it). 'test' marks a run from the admin test page,
  -- which never sends a real push regardless of channel availability.
  status text not null default 'matched'
    check (status in ('matched','notified','opened','audio_played','saved','test')),
  notification_variant_id text,
  notification_title text,
  notification_body text,
  narration_script text,
  narration_audio_url text,
  error text,
  created_at timestamptz not null default now(),
  notified_at timestamptz,
  opened_at timestamptz,
  audio_played_at timestamptz
);

-- The repeat-protection constraint itself: at most one match record per
-- (event, user) -- re-scoring an event a user was already matched against
-- updates this row rather than creating a second one.
create unique index if not exists event_matches_event_user_unique
  on public.event_matches(event_id, user_id);
create index if not exists event_matches_user_idx on public.event_matches(user_id);
create index if not exists event_matches_status_idx on public.event_matches(status);

alter table public.event_matches enable row level security;
do $$
begin
  execute 'drop policy if exists "event_matches_self_read" on public.event_matches';
  execute 'create policy "event_matches_self_read" on public.event_matches for select to authenticated using (auth.uid() = user_id)';
  -- Admin test-mode page and the matching engine both write via the
  -- authenticated app client today (no is_admin() role function exists in
  -- this project yet -- see discovered_events/event_sources for the same
  -- established pattern) -- tighten to admin-only if/when that role model
  -- is adopted project-wide.
  execute 'drop policy if exists "event_matches_authenticated_write" on public.event_matches';
  execute 'create policy "event_matches_authenticated_write" on public.event_matches for all to authenticated using (true) with check (true)';
end $$;

-- Forward-looking only, per spec ("design the architecture so it can be
-- added"): NOT wired to anything yet. Real push delivery (Firebase
-- Cloud Messaging or similar) requires an external project this migration
-- cannot create -- this table just means the schema is ready the moment
-- that's provisioned, without a later migration.
create table if not exists public.push_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null check (platform in ('android','ios')),
  push_token text not null,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  unique (user_id, push_token)
);
alter table public.push_devices enable row level security;
do $$
begin
  execute 'drop policy if exists "push_devices_self_all" on public.push_devices';
  execute 'create policy "push_devices_self_all" on public.push_devices for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id)';
end $$;
