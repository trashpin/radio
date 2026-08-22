-- Ocala Forest Explorer — an isolated experimental feature.
--
-- Two brand-new tables, never touching `locations`, `county_boundaries`,
-- `park_boundaries`, or any existing Marion County table:
--   forest_boundaries — real, authoritative polygon geometry (never a
--     circle or bounding box). Seeded with Ocala National Forest, sourced
--     from the USDA Forest Service's public ArcGIS REST service
--     (EDW_RangerDistricts_03: Lake George Ranger District + Seminole
--     Ranger District — together these ARE Ocala National Forest per
--     USFS's own administrative structure; there is no district literally
--     named "Ocala"). Fetched live via
--     https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_RangerDistricts_03/MapServer/0
--     (outSR=4326, f=geojson) and combined into one MultiPolygon-shaped
--     `polygon` value (12 parts: 2 main bodies + 10 small detached
--     inholding parcels, matching real national-forest checkerboard
--     ownership).
--   forest_locations — geographic features inside the forest. Seeded with
--     7 real, individually-verified (via point-in-polygon against the
--     geometry above) recreation sites; nothing here is fabricated.
--
-- Idempotent: safe to re-run.

create extension if not exists "pgcrypto";

create table if not exists public.forest_boundaries (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  source      text,
  source_url  text,
  polygon     jsonb not null,
  acres       numeric,
  created_at  timestamptz not null default now()
);

create table if not exists public.forest_locations (
  id                      uuid primary key default gen_random_uuid(),
  forest_id               uuid references public.forest_boundaries(id) on delete cascade,
  name                    text not null,
  category                text not null,
  latitude                double precision not null,
  longitude               double precision not null,
  description             text,
  source                  text,
  source_url              text,
  geofence_radius_meters  double precision,
  narration_short         text,
  narration_long          text,
  audio_url               text,
  tell_me_more            text,
  image_url               text,
  active                  boolean not null default true,
  created_at              timestamptz not null default now()
);

create index if not exists forest_locations_forest_idx
  on public.forest_locations (forest_id);

-- RLS: public read; admin (anon/authenticated) write — mirrors
-- what_is_that_place_data / location_content.
alter table public.forest_boundaries enable row level security;
alter table public.forest_locations enable row level security;

do $$
begin
  execute 'drop policy if exists "forest_boundaries_read" on public.forest_boundaries';
  execute 'create policy "forest_boundaries_read" on public.forest_boundaries '
          'for select to anon, authenticated using (true)';
  execute 'drop policy if exists "forest_boundaries_write" on public.forest_boundaries';
  execute 'create policy "forest_boundaries_write" on public.forest_boundaries '
          'for insert to anon, authenticated with check (true)';
  execute 'drop policy if exists "forest_boundaries_update" on public.forest_boundaries';
  execute 'create policy "forest_boundaries_update" on public.forest_boundaries '
          'for update to anon, authenticated using (true) with check (true)';

  execute 'drop policy if exists "forest_locations_read" on public.forest_locations';
  execute 'create policy "forest_locations_read" on public.forest_locations '
          'for select to anon, authenticated using (true)';
  execute 'drop policy if exists "forest_locations_write" on public.forest_locations';
  execute 'create policy "forest_locations_write" on public.forest_locations '
          'for insert to anon, authenticated with check (true)';
  execute 'drop policy if exists "forest_locations_update" on public.forest_locations';
  execute 'create policy "forest_locations_update" on public.forest_locations '
          'for update to anon, authenticated using (true) with check (true)';
end $$;

-- Seed: the real Ocala National Forest boundary (Lake George + Seminole
-- Ranger Districts combined), captured into a variable so the 7 seed
-- locations below can reference its id. Only seeds when the table is
-- empty, so re-running this migration never duplicates rows.
do $$
declare
  v_forest_id uuid;
begin
  if exists (select 1 from public.forest_boundaries where name = 'Ocala National Forest') then
    return;
  end if;

  insert into public.forest_boundaries (name, source, source_url, polygon, acres)
  values (
    'Ocala National Forest',
    'USDA Forest Service — EDW_RangerDistricts_03 (Lake George Ranger District + Seminole Ranger District)',
    'https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_RangerDistricts_03/MapServer/0',
    '[[[[-81.84315,29.52132],[-81.8877,29.50945],[-81.90119,29.51615],[-81.91114,29.50549],[-81.90975,29.47811],[-81.92935,29.42762],[-81.90082,29.39383],[-81.90129,29.37152],[-81.88403,29.33867],[-81.91673,29.29576],[-81.9361,29.28475],[-81.9423,29.26508],[-81.96514,29.2541],[-81.96706,29.23835],[-81.98614,29.21475],[-81.95077,29.21192],[-81.865,29.17185],[-81.70839,29.17818],[-81.6509,29.167],[-81.62245,29.17142],[-81.57004,29.15348],[-81.52476,29.16314],[-81.53269,29.177],[-81.55498,29.18425],[-81.56159,29.19943],[-81.61226,29.20287],[-81.64923,29.29175],[-81.67513,29.3097],[-81.67813,29.33553],[-81.65651,29.34026],[-81.66299,29.36402],[-81.68663,29.38843],[-81.68336,29.39859],[-81.68039,29.39188],[-81.65962,29.39206],[-81.66516,29.39815],[-81.65636,29.41929],[-81.69329,29.43716],[-81.69064,29.47033],[-81.72921,29.48378],[-81.76966,29.47207],[-81.79411,29.49564],[-81.80768,29.49634],[-81.81103,29.50902],[-81.84315,29.52132]]],[[[-82.06082,29.82781],[-82.06347,29.83471],[-82.06913,29.83125],[-82.06344,29.83243],[-82.06082,29.82781]]],[[[-81.51845,29.14683],[-81.5238,29.16735],[-81.57004,29.15348],[-81.62245,29.17142],[-81.6509,29.167],[-81.70839,29.17818],[-81.86418,29.17176],[-81.95077,29.21192],[-81.98614,29.21475],[-81.995,29.20164],[-81.99236,29.18363],[-81.9656,29.17355],[-81.93349,29.14251],[-81.92367,29.1099],[-81.906,29.09144],[-81.85423,29.09154],[-81.84624,29.04397],[-81.83235,29.03476],[-81.82822,29.01489],[-81.80789,29.0079],[-81.80761,28.99676],[-81.82829,28.99349],[-81.80755,28.99347],[-81.77148,28.97552],[-81.71354,28.98947],[-81.65988,28.96626],[-81.65891,28.98583],[-81.65175,28.98579],[-81.65886,28.98938],[-81.65896,29.00407],[-81.6443,29.00381],[-81.62715,28.98789],[-81.63971,28.98945],[-81.63979,28.97848],[-81.6248,28.97098],[-81.61039,28.97862],[-81.61046,28.96759],[-81.58126,28.96023],[-81.54235,28.97545],[-81.5343,29.00333],[-81.51599,29.01457],[-81.47377,29.0168],[-81.4331,29.00403],[-81.38259,29.0082],[-81.4557,29.06278],[-81.45918,29.09363],[-81.48829,29.09247],[-81.51853,29.10791],[-81.5064,29.1243],[-81.51845,29.14683]]],[[[-81.09698,28.62736],[-81.09659,28.62701],[-81.0966,28.62736],[-81.09698,28.62736]]],[[[-81.09666,28.6474],[-81.10066,28.63461],[-81.09228,28.62735],[-81.09069,28.65301],[-81.09666,28.6474]]],[[[-81.10078,28.64373],[-81.09871,28.64496],[-81.1008,28.64494],[-81.10078,28.64373]]],[[[-81.09699,28.65784],[-81.09686,28.65282],[-81.09646,28.66387],[-81.09717,28.66387],[-81.09699,28.65784]]],[[[-81.48891,28.92028],[-81.48445,28.9167],[-81.4844,28.92043],[-81.48891,28.92028]]],[[[-81.43841,28.94894],[-81.43397,28.95622],[-81.4381,28.95622],[-81.43841,28.94894]]],[[[-81.42969,28.96344],[-81.42542,28.96752],[-81.42951,28.96754],[-81.42969,28.96344]]],[[[-81.51723,28.97813],[-81.51289,28.98212],[-81.51724,28.98217],[-81.51723,28.97813]]],[[[-81.52291,29.00016],[-81.52189,28.99313],[-81.51402,28.99669],[-81.51457,29.00021],[-81.52291,29.00016]]]]'::jsonb,
    443169.11
  )
  returning id into v_forest_id;

  -- 7 real, individually verified recreation sites (each confirmed inside
  -- the polygon above via a ray-casting point-in-polygon check before
  -- being added here — never assumed "close enough").
  insert into public.forest_locations
    (forest_id, name, category, latitude, longitude, description, source, source_url)
  values
    (v_forest_id, 'Alexander Springs', 'Spring',
      29.0788915, -81.5780407,
      'A first-magnitude spring and recreation area on the eastern side of Ocala National Forest, popular for swimming, snorkeling, and canoeing.',
      'USDA Forest Service', 'https://www.fs.usda.gov/r08/florida/recreation/alexander-springs-recreation-area'),
    (v_forest_id, 'Juniper Springs', 'Spring',
      29.18389, -81.71194,
      'A historic CCC-era spring and recreation area with a swimming basin and the Juniper Run canoe trail.',
      'Wikipedia / USDA Forest Service', 'https://en.wikipedia.org/wiki/Juniper_Springs'),
    (v_forest_id, 'Silver Glen Springs', 'Spring',
      29.2468, -81.6435,
      'A large second-magnitude spring feeding into Lake George, known for exceptionally clear water and swimming.',
      'Wikipedia', 'https://en.wikipedia.org/wiki/Silver_Glen_Springs'),
    (v_forest_id, 'Salt Springs', 'Spring',
      29.35111, -81.735,
      'A large spring and recreation area near the northern edge of the forest, with a run connecting to Lake George.',
      'Wikipedia / USDA Forest Service', 'https://www.fs.usda.gov/r08/florida/recreation/salt-springs-recreation-area'),
    (v_forest_id, 'Salt Springs Trailhead', 'Trailhead',
      29.354897, -81.734478,
      'Trailhead access point near Salt Springs.',
      'USDA Forest Service', 'https://www.fs.usda.gov/r08/florida/recreation/salt-springs-recreation-area'),
    (v_forest_id, 'Lake Dorr Recreation Area', 'Lake / Campground',
      29.0143142, -81.6357021,
      'A recreation area and campground on Lake Dorr in the southern part of the forest.',
      'USDA Forest Service', 'https://www.fs.usda.gov/r08/florida/recreation/lake-dorr-recreation-area'),
    (v_forest_id, 'Clearwater Lake Recreation Area', 'Lake / Campground',
      28.97851, -81.553909,
      'A campground and day-use area along the southeastern edge of the forest near Paisley, with a beach and picnic area.',
      'Wikipedia / USDA Forest Service', 'https://www.fs.usda.gov/r08/florida/recreation/clearwater-lake-recreation-area');
end $$;
