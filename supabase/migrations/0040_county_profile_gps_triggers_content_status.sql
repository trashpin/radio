-- ExplorerOS — County Content Management System, Phase 1: schema extensions.
--
-- Extends the existing `counties` table with the full County Profile fields
-- (seal, hero image, history/overview, population, size, year established,
-- facts, tourism info, official website, gallery) and extends `locations`
-- with per-location GPS trigger behavior (arrival/departure/play-once/
-- cooldown) plus an explicit editorial content-status workflow.
--
-- Additive only: no existing column is renamed, removed, or repurposed, and
-- every new column has a safe default (or is nullable), so existing rows and
-- existing app code both keep working unchanged.
--
-- Idempotent: safe to re-run.

-- ── County Profile (extends the existing `counties` table) ─────────────────
alter table public.counties
  add column if not exists seal_url             text,
  add column if not exists hero_image_url        text,
  -- Audio companion to the existing `welcome` text (kept as-is — it's the
  -- spoken script; this is the generated narration file, matching the
  -- script/audio pairing used elsewhere in the app, e.g. nearby_gems).
  add column if not exists welcome_narration_url text,
  add column if not exists history               text,
  add column if not exists overview              text,
  add column if not exists population            bigint,
  add column if not exists size_sq_miles         double precision,
  add column if not exists year_established      integer,
  add column if not exists facts                 text[] not null default '{}',
  add column if not exists tourism_info          text,
  add column if not exists official_website      text,
  add column if not exists gallery_images        text[] not null default '{}';

-- ── Per-location GPS trigger configuration (extends `locations`) ───────────
-- `trigger_radius` and `priority` already exist and are already per-row —
-- there is no global trigger radius today, so nothing to change there.
alter table public.locations
  add column if not exists arrival_trigger   boolean not null default true,
  add column if not exists departure_trigger boolean not null default false,
  add column if not exists play_once         boolean not null default false,
  add column if not exists cooldown_seconds  integer;

-- ── Content status workflow (extends `locations`) ───────────────────────────
-- Explicit editorial status, separate from the app's existing COMPUTED
-- status (derived client-side from active/hidden/hasAudio — see
-- MasterLocation.status in Dart, left untouched). Nullable: existing rows
-- fall back to a computed default (MasterLocation.effectiveContentStatus)
-- until an admin sets one explicitly, so nothing that reads the old computed
-- status breaks.
alter table public.locations
  add column if not exists content_status text;

alter table public.locations
  drop constraint if exists locations_content_status_check;
alter table public.locations
  add constraint locations_content_status_check
  check (content_status is null or content_status in (
    'draft', 'needs_images', 'needs_narration',
    'needs_gps_verification', 'needs_review', 'published', 'archived'
  ));

create index if not exists locations_content_status_idx
  on public.locations (content_status);
