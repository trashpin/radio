-- Marion County Adventures — Treasure Hunt Discovery stage: a second
-- exploration layer AFTER GPS arrival, before the existing QR scan. Purely
-- additive and purely presentational -- does not touch the GPS/geofencing
-- pipeline (MissionStoryEngine/ActiveMissionController's arrival/QR logic
-- is completely unchanged), does not replace the existing QR system (a
-- treasure discovery still resolves through the stop's own existing
-- qr_portal_id -- there is no second QR mechanism here), and does not
-- touch any location record.
--
-- GPS still gets the player to the stop's existing arrival_radius_meters.
-- This table only adds what happens AFTER that arrival and BEFORE the
-- player taps into the existing QR scanner: a stylized map + clue + a
-- progressive hint ladder that encourages physically looking around
-- instead of walking straight to a GPS pin.

create table if not exists public.treasure_discoveries (
  id uuid primary key default gen_random_uuid(),
  mission_id uuid not null references public.missions(id) on delete cascade,
  stop_id uuid not null references public.mission_stops(id) on delete cascade,
  -- Mystery/adventure artwork of the real search area -- NOT a GPS map and
  -- NOT a pin on the exact QR spot (spec: "Do not place a giant GPS marker
  -- directly on the QR location"). Null shows a styled placeholder panel
  -- rather than nothing, so the stage still works before real art exists.
  treasure_map_image_url text,
  clue_text text,
  -- Progressive hint ladder -- each is optional; the "Need a Hint?" UI
  -- only offers hints that are actually set. Requesting a hint has a small
  -- XP cost applied at the eventual QR scan (see ActiveMissionController),
  -- never punitive (spec: "do not punish the player heavily").
  hint_1_text text,
  hint_2_text text,
  final_hint_text text,
  -- Shown on "YOU FOUND IT" instead of a generic label, e.g. "YOU FOUND
  -- THE FIRST PIECE".
  discovery_title text,
  -- Admin-facing production notes (real landmarks a clue references) --
  -- not required to be shown to the player as-is; the clue text is what
  -- the player actually reads.
  landmarks_text text,
  -- Free text, not a fixed enum -- matches this schema's existing
  -- category/difficulty philosophy. Suggested vocabulary: easy, medium,
  -- hard.
  difficulty text,
  -- Optional, soft-bounded search guidance ("somewhere within about
  -- __ of here") -- deliberately never the exact QR distance/bearing.
  search_area_meters double precision,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Mirrors how mission_stops already links to qr_portal_id/old_world_id --
-- one treasure discovery per stop, referenced the same way. The QR itself
-- is NOT duplicated here: a treasure discovery always resolves through the
-- stop's own EXISTING qr_portal_id, the same portal the plain "Scan QR
-- Marker" flow already used before this feature existed.
alter table public.mission_stops
  add column if not exists treasure_discovery_id uuid references public.treasure_discoveries(id) on delete set null;

create index if not exists treasure_discoveries_mission_idx on public.treasure_discoveries(mission_id);
create index if not exists treasure_discoveries_stop_idx on public.treasure_discoveries(stop_id);

alter table public.treasure_discoveries enable row level security;
do $$
begin
  execute 'create policy "treasure_discoveries_read" on public.treasure_discoveries for select to anon, authenticated using (true)';
  execute 'create policy "treasure_discoveries_write" on public.treasure_discoveries for all to authenticated using (true) with check (true)';
end $$;
