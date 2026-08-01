-- ExplorerOS — Nearby Gems ranking signals
--
-- The traveler "Nearby Gems" discovery sorts results within a configurable
-- radius (5 or 10 miles) by a composite of featured status, editorial priority,
-- popularity, and distance. These columns back that ranking (all optional; the
-- app defaults them to false/0 when absent).
--
-- Idempotent: safe to re-run.

alter table public.nearby_gems
  add column if not exists featured   boolean not null default false,
  add column if not exists priority   integer not null default 0,
  add column if not exists popularity integer not null default 0;

-- Helps ordering/scanning when the list grows.
create index if not exists nearby_gems_rank_idx
  on public.nearby_gems (featured desc, priority desc, popularity desc);
