-- Reconstructed from the live database (this table, its enum, its RPC, and
-- geofence_level_defaults existed live with real data but had never been
-- committed as a migration — a repo/DB drift gap found during the Marion
-- County Adventures audit). This file makes the schema reproducible again;
-- it does not change any live behavior.
--
-- The hierarchical geofence system: an 11-level hierarchy (State..POI, see
-- GeofenceLevel in lib/features/gps/models/geofence_level.dart) where the
-- deepest containing boundary always wins, with priority as a same-depth
-- tiebreak. `get_nearby_geofences` is the single runtime source of truth for
-- GPS-triggered location radio and (going forward) Mission Stop arrival
-- detection -- no client-side geodesic recomputation.

do $$
begin
  if not exists (select 1 from pg_type where typname = 'geofence_level') then
    create type public.geofence_level as enum (
      'state', 'county', 'city', 'district', 'neighborhood', 'park',
      'historic_site', 'museum', 'trail', 'business', 'poi'
    );
  end if;
end $$;

create table if not exists public.geofence_level_defaults (
  level geofence_level primary key,
  default_priority integer not null
);

insert into public.geofence_level_defaults (level, default_priority) values
  ('state', 20), ('county', 40), ('city', 60), ('district', 65),
  ('neighborhood', 70), ('park', 80), ('business', 82), ('trail', 85),
  ('historic_site', 90), ('museum', 95), ('poi', 100)
on conflict (level) do nothing;

create table if not exists public.geofences (
  id uuid primary key default gen_random_uuid(),
  location_id uuid not null references public.locations(id),
  level geofence_level not null,
  parent_id uuid references public.geofences(id),
  center_lat double precision not null,
  center_lng double precision not null,
  radius_meters double precision not null,
  priority_override integer,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.geofence_level_defaults enable row level security;
alter table public.geofences enable row level security;
do $$
begin
  execute 'drop policy if exists "geofence_level_defaults_read" on public.geofence_level_defaults';
  execute 'create policy "geofence_level_defaults_read" on public.geofence_level_defaults for select to anon, authenticated using (true)';

  execute 'drop policy if exists "geofences_read" on public.geofences';
  execute 'create policy "geofences_read" on public.geofences for select to anon, authenticated using (true)';
  execute 'drop policy if exists "geofences_write" on public.geofences';
  execute 'create policy "geofences_write" on public.geofences for insert to anon, authenticated with check (true)';
  execute 'drop policy if exists "geofences_update" on public.geofences';
  execute 'create policy "geofences_update" on public.geofences for update to anon, authenticated using (true) with check (true)';
  execute 'drop policy if exists "geofences_delete" on public.geofences';
  execute 'create policy "geofences_delete" on public.geofences for delete to anon, authenticated using (true)';
end $$;

-- The proximity RPC every geofence-aware feature reads through
-- (GeofenceRepository.nearby, and now the Mission approach/arrival engine).
create or replace function public.get_nearby_geofences(user_lat double precision, user_lng double precision)
returns table(
  geofence_id uuid, location_id uuid, location_name text, location_category text,
  distance_meters double precision, radius_meters double precision, priority integer
)
language sql
set search_path to 'public'
as $function$
    select
        g.id as geofence_id,
        g.location_id,
        l.name as location_name,
        l.category as location_category,

        6371000 * 2 * asin(
            sqrt(
                power(sin(radians(g.center_lat - user_lat) / 2), 2)
                + cos(radians(user_lat)) * cos(radians(g.center_lat))
                  * power(sin(radians(g.center_lng - user_lng) / 2), 2)
            )
        ) as distance_meters,

        g.radius_meters,
        coalesce(g.priority_override, 0) as priority

    from public.geofences g
    join public.locations l on l.id = g.location_id
    where g.active = true
    and (
        6371000 * 2 * asin(
            sqrt(
                power(sin(radians(g.center_lat - user_lat) / 2), 2)
                + cos(radians(user_lat)) * cos(radians(g.center_lat))
                  * power(sin(radians(g.center_lng - user_lng) / 2), 2)
            )
        )
    ) <= g.radius_meters
    order by priority desc, distance_meters asc;
$function$;
