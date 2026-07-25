# Map Discovery Architecture — the "living digital ranger"

Real-time, GPS-driven discovery: as the visitor moves, the map surfaces nearby
wildlife, plants, trails, history, springs, and facilities automatically.

## Data
- **`map_locations`** (`supabase/migrations/0005_map_locations.sql`): every
  geolocated point — `id, park_code, category, subcategory, name, description,
  latitude, longitude, image_url, gallery_urls, audio_url, icon, visibility,
  featured, ai_context, keywords`. **Nothing hardcoded; all markers come from
  Supabase.** Performance path (documented in the migration): PostGIS
  `geography` column + GIST index + `ST_DWithin` for true geospatial queries.

## Folder structure
```
lib/features/maps/
  models/nearby_item.dart        # NearbyItem + per-category style (icon/color/group)
  providers/
    nearby_provider.dart         # SearchRadius, mapCenter, searchRadius,
                                 # mapLocations (repo), nearbyItems (radius filter, sorted)
    map_layers_provider.dart     # base layer toggles (parks/boundaries/locations/sightings)
  presentation/maps_screen.dart  # map + user dot + radius selector + Around Me + sheets
```

## Built this phase (verified on web with a simulated location)
- **User location**: blue dot + GPS accuracy ring at the current center; a
  **Recenter** control animates to it. (Device GPS on hardware; a simulated
  center — the first destination — on web where geolocation is unavailable.)
- **Search radius selector**: 100 ft → Entire Park; changing it re-filters and
  re-fits the camera.
- **Nearby search**: `nearbyItemsProvider` computes items within the radius
  (haversine) sorted nearest-first, from `map_locations`.
- **Dynamic category markers**: one icon per category, only within radius.
- **Smart camera**: fits user + nearby markers into view on radius change.
- **Around Me panel**: draggable bottom sheet grouping nearby items by category
  with counts, each expandable into distance-sorted items; tapping one zooms the
  map and opens the item sheet.
- **Item sheet**: image, name, distance, description + action buttons (Navigate,
  Play Audio, Gallery, Favorite, Journal, Ask AI Ranger — placeholders).
- **Tap-to-explore**: tapping any marker opens its detail sheet (parks can
  "Tune Radio").

## Roadmap (designed for; not yet built)
- **Continuous auto-follow** + "manual pan disables follow": swap the simulated
  center for `GPSService`'s live stream (`geolocator`), update `mapCenter` on
  each fix; disable follow on user gesture, re-enable via Recenter. Needs device
  GPS.
- **Animated marker in/out** (fade) as items enter/leave the radius.
- **Explorer Mode**: a toggle that scans on each location change and shows
  subtle, non-interrupting notifications ("Approaching Juniper Spring").
- **GPS story triggers**: invisible trigger zones → pause Explorer Radio, play
  the location's narration, resume after; fire once per entry. Reuses the
  existing `GPSService` geofence + `TravelCompanionService` + Radio engine
  (`requestInterruption`) — the engine already exists; this wires it to
  `map_locations` zones.
- **Heat-map layers** (wildlife activity, bird sightings, blooms, fishing,
  photography, scenic, night-sky, migrations): the layer system
  (`map_layers_provider`) is built to add overlay layers without rewriting the
  map — each new layer = a provider + a renderer (markers/heatmap tiles).
- **Performance at scale**: server-side bounding-box/PostGIS queries (only fetch
  what's near), marker **clustering** when zoomed out, lazy-loaded/cached images,
  and the existing `CacheStore` for offline nearby data.

## Reuse (no duplication)
Existing `GoogleMap` + `_circleIconMarker`, `GPSService`/`TravelContext`/
geofence, `TravelCompanionService` + Radio engine (for triggers), `CacheStore`
(caching/offline), design tokens. Discovery categories/styles are shared with
the "I See Something" guide.
