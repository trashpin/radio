-- Ocala Forest Explorer — DISCOVER: community photo-identified discoveries.
--
-- A new, isolated table (never touching `explorer_sightings` -- that table
-- is a separate, pre-existing stub already earmarked by this repo's own
-- docs to become a different future "journal" capture path; extending it
-- here would fight that plan) and never touching `locations`/
-- `county_boundaries`/`species`/Marion County content. Reuses the SAME
-- forest_boundaries/forest_trails this feature already has.
--
-- Two distinct status axes, both required by the spec:
--   moderation_status -- has an admin/the community process reviewed this?
--                         (pending/confirmed/needs_review/rejected)
--   visibility        -- how precisely is the location shown to the public?
--                         (public/generalized/private)
-- A discovery can be `confirmed` but still `generalized` (e.g. a verified
-- rare-species sighting whose exact den location must stay protected) --
-- these two axes are independent on purpose.
--
-- Idempotent: safe to re-run.

create table if not exists public.forest_discovery_reports (
  id                  uuid primary key,
  forest_id           uuid references public.forest_boundaries(id),
  trail_id            uuid references public.forest_trails(id), -- set when reported while on a known trail (spec §13); null otherwise
  species_id          uuid references public.species(species_id), -- deterministic name-match only, never AI-inferred (spec §12 wildlife-page connection)

  -- What the visitor says they found.
  category            text not null, -- wildlife|birds|plants_nature|water|geology|history|other (spec §2)
  subtype             text,          -- e.g. 'animal','tracks_signs','reptile','spring','historic_structure',… free text, not invented if absent
  identification      text,          -- the visitor's final confirmed/edited name -- NEVER auto-set from the AI suggestion alone
  scientific_name      text,
  user_confirmation   text not null default 'unknown'
    check (user_confirmation in ('accepted', 'edited', 'unknown')), -- spec §4: accept / pick another / submit as unknown

  -- The photo (spec §3/§5) -- central to this flow.
  photo_url           text not null,

  -- Captured via the EXISTING GPS system (spec §5) -- never a new one.
  latitude            double precision not null,
  longitude           double precision not null,
  observed_at         timestamptz not null default now(),

  user_notes          text,

  -- The AI's suggestion, preserved distinctly and permanently from whatever
  -- the visitor ultimately confirms -- spec §4: "must not automatically
  -- become verified information."
  ai_identification   text,
  ai_scientific_name  text,
  ai_confidence       text check (ai_confidence in ('high', 'medium', 'low', null)),
  ai_explanation      text,
  ai_caveats          text,

  -- Moderation (spec §11) -- community content stays clearly separate from
  -- official/verified information until reviewed.
  moderation_status   text not null default 'pending'
    check (moderation_status in ('pending', 'confirmed', 'needs_review', 'rejected')),

  -- Sensitive-location protection (spec §10) -- exact coordinates are only
  -- ever exposed publicly when visibility = 'public'; enforced in
  -- forest_discovery_reports_public below, not left to client-side trust.
  visibility          text not null default 'public'
    check (visibility in ('public', 'generalized', 'private')),
  is_sensitive        boolean not null default false,

  reporter_id         text not null default 'anonymous', -- no real per-user auth exists yet in this app; matches explorer_sightings' own convention
  source              text not null default 'community',

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index if not exists forest_discovery_reports_forest_idx
  on public.forest_discovery_reports (forest_id);
create index if not exists forest_discovery_reports_category_idx
  on public.forest_discovery_reports (category);
create index if not exists forest_discovery_reports_species_idx
  on public.forest_discovery_reports (species_id);
create index if not exists forest_discovery_reports_moderation_idx
  on public.forest_discovery_reports (moderation_status);

drop trigger if exists forest_discovery_reports_set_updated_at on public.forest_discovery_reports;
create trigger forest_discovery_reports_set_updated_at
  before update on public.forest_discovery_reports
  for each row execute function public.media_assets_touch_updated_at(); -- generic "set updated_at = now()" trigger fn, already defined by migration 0025

-- Deterministic, exact-name species linkage (spec §12: "connect DISCOVER to
-- existing wildlife pages") -- a plain case-insensitive match against
-- species.common_name, computed server-side so it's applied consistently
-- regardless of which client inserts the row. Never AI-inferred: this only
-- ever fires off the visitor's own final confirmed/edited `identification`
-- text, not the raw AI suggestion.
create or replace function public.forest_discovery_reports_match_species()
returns trigger
language plpgsql
as $$
begin
  if new.species_id is null and new.identification is not null then
    select species_id into new.species_id
    from public.species
    where lower(common_name) = lower(trim(new.identification))
    limit 1;
  end if;
  return new;
end;
$$;

drop trigger if exists forest_discovery_reports_species_match on public.forest_discovery_reports;
create trigger forest_discovery_reports_species_match
  before insert or update on public.forest_discovery_reports
  for each row execute function public.forest_discovery_reports_match_species();

alter table public.forest_discovery_reports enable row level security;

-- Insert/update/delete follow this app's existing wide-open convention
-- (every other admin-writable table here uses the same `using (true)` --
-- admin gating in this codebase is UI-level, not RLS-level; see 0025/0048).
drop policy if exists "forest_discovery_reports_insert" on public.forest_discovery_reports;
create policy "forest_discovery_reports_insert" on public.forest_discovery_reports
  for insert to anon, authenticated with check (true);

drop policy if exists "forest_discovery_reports_update" on public.forest_discovery_reports;
create policy "forest_discovery_reports_update" on public.forest_discovery_reports
  for update to anon, authenticated using (true) with check (true);

drop policy if exists "forest_discovery_reports_delete" on public.forest_discovery_reports;
create policy "forest_discovery_reports_delete" on public.forest_discovery_reports
  for delete to anon, authenticated using (true);

-- Deliberately NO select policy for anon/authenticated: this is the one
-- deviation from the wide-open convention above, and it's intentional --
-- spec §10 calls sensitive-location protection "extremely important," and
-- the ONLY way to guarantee exact coordinates never leak (regardless of
-- what a client tries to query) is to make the raw table unreadable by the
-- public client entirely and force every public read through the view
-- below, which computes the generalized coordinates itself. The app's own
-- "Discovery Saved" screen renders from the payload it already has in
-- memory right after a successful insert, so it never needs to read this
-- table back.

-- Public read surface: excludes private/rejected discoveries entirely, and
-- rounds lat/lng to ~1km precision for anything not fully public. This
-- view runs with its owner's privileges (the default for a plain view),
-- which is what lets it see the RLS-locked base table above while still
-- enforcing its own row/column rules for anon/authenticated callers.
create or replace view public.forest_discovery_reports_public as
  select
    id, forest_id, trail_id, species_id,
    category, subtype, identification, scientific_name, photo_url,
    case when visibility = 'public' then latitude
         else round(latitude::numeric, 2)::double precision end as latitude,
    case when visibility = 'public' then longitude
         else round(longitude::numeric, 2)::double precision end as longitude,
    (visibility <> 'public') as location_generalized,
    observed_at, user_notes,
    ai_identification, ai_scientific_name, ai_confidence, ai_explanation,
    user_confirmation, moderation_status, is_sensitive, source, created_at
  from public.forest_discovery_reports
  where visibility <> 'private' and moderation_status <> 'rejected';

-- Admin moderation (spec §11) needs to see EVERY row (all statuses, exact
-- coordinates) despite the base table having no anon/authenticated SELECT
-- policy. This app has no separate DB role for "the admin screen" versus
-- "the public app" (every other admin table here is just wide-open RLS,
-- gated only by which Flutter screen you're on) -- rather than reopen the
-- table (which would defeat the coordinate-generalization guarantee for
-- ANY caller, not just the admin UI), these two SECURITY DEFINER functions
-- give the admin moderation screen a working, still-narrow path: they run
-- with the function owner's privileges (bypassing the base table's RLS by
-- design, the same way a superuser-created view already does), so only
-- code that explicitly calls them can see/change the raw table.
create or replace function public.forest_discovery_admin_list()
returns setof public.forest_discovery_reports
language sql
security definer
set search_path = public
as $$
  select * from public.forest_discovery_reports order by created_at desc;
$$;

create or replace function public.forest_discovery_admin_set_status(
  p_id uuid,
  p_moderation_status text default null,
  p_visibility text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.forest_discovery_reports
  set moderation_status = coalesce(p_moderation_status, moderation_status),
      visibility = coalesce(p_visibility, visibility)
  where id = p_id;
end;
$$;

-- Public `forest_discovery_photos` Storage bucket -- mirrors the existing
-- `media`/`music_audio` buckets' open pattern (this app has no per-user
-- storage privacy precedent anywhere; the privacy guarantee for this
-- feature lives in the coordinate generalization above, not in hiding the
-- photo file itself).
insert into storage.buckets (id, name, public)
values ('forest_discovery_photos', 'forest_discovery_photos', true)
on conflict (id) do nothing;

do $$
begin
  execute 'drop policy if exists "forest_discovery_photos_read" on storage.objects';
  execute 'create policy "forest_discovery_photos_read" on storage.objects '
          'for select to anon, authenticated using (bucket_id = ''forest_discovery_photos'')';

  execute 'drop policy if exists "forest_discovery_photos_write" on storage.objects';
  execute 'create policy "forest_discovery_photos_write" on storage.objects '
          'for insert to anon, authenticated with check (bucket_id = ''forest_discovery_photos'')';
exception
  when insufficient_privilege then
    raise notice 'Skipping storage.objects policies (insufficient privilege).';
end $$;
