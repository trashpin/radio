# ExplorerOS — GPS Intelligence Engine Architecture

The GPS Intelligence Engine is a core system of ExplorerOS. It is **not** a GPS
location service — it understands where the user is, where they are going, what
they have visited, and turns raw fixes into a rich, published `TravelContext`
plus a stream of domain **events** that the rest of the app reacts to.

It has **no map-SDK dependency** and **plays/renders nothing**. Positioning
comes through a swappable `LocationProvider`, and consumers subscribe to events
instead of polling.

---

## 1. Folder structure

`lib/features/gps/`

| Folder | Responsibility |
| --- | --- |
| `models/` | Immutable value types: fixes, derived state, boundaries, and the published `TravelContext`. |
| `events/` | The `GpsEvent` vocabulary published on the engine's event bus. |
| `services/` | The engine and its single-responsibility sub-services (tracking, speed, heading, distance, detection, geofencing, context assembly, cache). |
| `repositories/` | Data access: park/state boundaries (read-only content) and location history (user data, synced). |
| `controllers/` | `GpsController` — the Riverpod `Notifier<TravelContext>` the UI/coordinators watch. |
| `providers/` | Dependency-injection wiring (service singletons + the composed engine). |
| `utils/` | `GeoMath` — pure great-circle distance/bearing math. |

---

## 2. Classes

### Models
- **GPSLocation** — one positioning fix (lat/lng/accuracy/altitude/heading/speed/timestamp); serializable for caching.
- **GPSHeading** — travel direction as degrees + `CardinalDirection`.
- **SpeedState** — a speed plus its classified `MovementState`/`TravelMode` (km/h & mph getters).
- **TravelState** — high-level travel summary (movement + mode + parked + distance).
- **RouteProgress** — distance travelled + next stop + distance/ETA + fraction complete.
- **NearbyDestination / UpcomingDestination** — attractions near / ahead (with distance, bearing, ETA).
- **CurrentDestination** — the destination the user is at, with `ArrivalStatus` + since.
- **VisitedDestination** — a visited attraction (user data; `toJson` for sync).
- **GeofenceRegion** — a circular fence with `contains()`.
- **ParkBoundary / StateBoundary** — park (circle) and state (bbox) extents (read-only content).
- **LocationSnapshot** — in-memory cache entry (fix + resolved context).
- **TravelSnapshot** — persisted history record (fix + context; `toJson` for Supabase).
- **TravelStatistics** — cumulative trip stats (distance, max speed, parks/attractions visited).
- **TravelContext** — THE published output (see §6).
- Enums: `TravelMode`, `MovementState`, `ArrivalStatus`, `GpsTrackingStatus`, `GpsProviderType`, `CardinalDirection`.

### Services
- **GPSService** — the engine/brain. Orchestrates the pipeline, assembles context, emits events, exposes the public API.
- **LocationTrackingService** — manages the provider subscription (start/pause/resume/stop) and forwards fixes.
- **LocationProvider** (+ `SimulatedLocationProvider`) — the positioning abstraction (swap in system/Google/Apple/offline).
- **SpeedService** — classifies speed → movement + travel mode.
- **HeadingService** — resolves heading from device or consecutive fixes.
- **DistanceService** — distance + ETA calculations.
- **RouteEngine** — accumulates distance travelled; computes next-stop progress/ETA.
- **GeofenceService** — enter/exit transition detection.
- **ParkDetectionService** — current park + arrival state machine.
- **DestinationDetectionService** — nearby + upcoming detection + visited tracking.
- **StateDetectionService** — current state from boundaries.
- **TravelContextService** — assembles the `TravelContext`.
- **GPSCacheService** — rolling buffer of `LocationSnapshot`s (offline continuity).

### Repositories
- **ParkBoundaryRepository / StateBoundaryRepository** — read-only geometry (generic base).
- **LocationRepository** — user location history (`TravelSnapshot`), sync-capable.
- Destination/park **content** is reused from `features/destinations` (`DestinationRepository`, `ParkRepository`) — not duplicated.

### Controller / Providers
- **GpsController** — `Notifier<TravelContext>`; subscribes to the engine stream and forwards commands.
- **providers/gps_providers.dart** — wires every service as a scope singleton and composes `GPSService`.

---

## 3. Architecture diagram

```mermaid
flowchart TD
  LP[LocationProvider\n(system/Google/Apple/offline)] --> LT[LocationTrackingService]
  LT -->|GPSLocation fix| ENG[GPSService]
  subgraph Pipeline
    ENG --> SP[SpeedService]
    ENG --> HD[HeadingService]
    ENG --> DS[DistanceService]
    ENG --> RE[RouteEngine]
    ENG --> GF[GeofenceService]
    ENG --> PD[ParkDetectionService]
    ENG --> SD[StateDetectionService]
    ENG --> DD[DestinationDetectionService]
  end
  ENG --> TCS[TravelContextService]
  TCS --> CTX[(TravelContext)]
  ENG --> CACHE[GPSCacheService]
  ENG --> BUS{{Event Bus: Stream<GpsEvent>}}
  CTX --> GC[GpsController]
  BUS --> RADIO[Radio Engine]
  BUS --> PROD[AI Producer]
  BUS --> STORY[Story Engine]
  CTX --> MAP[Map Screen]
  CTX --> EXP[Explorer Screen]
  REPO[(Supabase / Offline)] --> ENG
```

---

## 4. Event flow

The engine publishes on `GPSService.events` (`Stream<GpsEvent>`). Consumers
subscribe and filter; they never poll.

```
fix arrives
  → LocationUpdated
  → (state changed?)   ExitedState / EnteredState
  → (park changed?)    ExitedPark / EnteredPark
  → (arrival changed?) ApproachingDestination / ArrivedAtDestination / LeavingDestination
  → (speed changed?)   SpeedChanged
  → (movement toggled?) TravelStarted / TravelStopped
markVisited()          → DestinationVisited
provider signal lost   → GpsLost ; next fix → GpsRecovered
route re-configured    → RouteChanged
```

`GpsEvent` is a `sealed` class, so handlers can `switch` exhaustively.

---

## 5. Data flow

1. `LocationProvider` emits a `GPSLocation`.
2. `LocationTrackingService` forwards it to `GPSService.processLocation`.
3. The pipeline derives speed, heading, distance/route, geofence transitions,
   park, state, and nearby/upcoming destinations.
4. `TravelContextService` assembles an immutable `TravelContext`; stats update.
5. The engine caches a `LocationSnapshot`, emits the context on
   `travelContextStream`, and emits `GpsEvent`s for meaningful changes.
6. `GpsController` republishes the context; `LocationRepository` can persist a
   `TravelSnapshot` for history.

---

## 6. `TravelContext` — the contract for other engines

Contains everything the Radio Engine, AI Producer, and Story Engine need:
current state/county/region/park/destination, nearest + upcoming + visited
attractions, heading/bearing/speed/altitude, `routeProgress` (next stop, ETA,
fraction complete) + `distanceRemainingMeters`, estimated arrival, travel &
movement state, cumulative statistics, plus time-of-day/season (derived) and a
weather placeholder.

### How it connects
- **AI Producer** — a coordinator maps `TravelContext` → `ProducerContext`
  (`gpsLocation`, park/state, `upcomingAttraction` ← `nextAttraction`,
  time/season). The Producer returns a `PlaybackDecision`.
- **Radio Engine** — executes the Producer's decision; GPS `ApproachingDestination`/
  `EnteredPark` events trigger `requestInterruption` for location audio, and
  `ArrivedAtDestination` can drive welcome narration.
- **Story Engine** — subscribes to arrival/enter events to unlock/queue stories
  for the current park/stop; uses `visitedStopIds` to avoid repeats.
- **Map Screen** — watches `gpsControllerProvider` to render position, heading,
  nearby/upcoming pins, and the travelled path (from cache history).
- **Explorer Screen** — uses nearby/upcoming + distance to sort and badge
  destinations ("2 mi ahead", "visited").

---

## 7. Future expansion points

- **Real providers**: implement `LocationProvider` for `geolocator` (system),
  Google/Apple, and offline/downloaded-park positioning; select via
  `GpsProviderType` and override `locationProviderProvider`.
- **Reverse geocoding**: fill `currentRoad/currentCity/currentCounty` (currently
  placeholders) via a geocoding service.
- **Polygon boundaries**: replace circular `ParkBoundary`/bbox `StateBoundary`
  membership with precise polygons behind the same `contains()` contract.
- **Weather**: populate `TravelContext.weather` from a weather service.
- **Background/CarPlay/Android Auto**: a background isolate feeds fixes through
  the same `LocationProvider`; the engine and events are unchanged.
- **Persistent cache**: swap the in-memory `GPSCacheService`/`LocationRepository`
  backing store for on-device storage.

---

## 8. Best practices

- One responsibility per service; the engine only orchestrates.
- Pure, synchronous `processLocation` → trivially unit-testable (no timers/IO).
- Immutable models + a single published `TravelContext`.
- Event-driven fan-out (no polling); `sealed` events for exhaustive handling.
- Provider abstraction keeps the engine free of platform/map-SDK coupling.
- Table names and content access reuse the shared data layer (no duplication).

---

## 9. Performance considerations

- Detection is O(n) over park/state/attraction lists; scope candidates to the
  active destination/region (and cap nearby/upcoming radii + `limit`s).
- The engine allocates one immutable context per fix — cheap; avoid heavy work
  in event listeners (offload to microtasks/isolates if needed).
- For large datasets, add a spatial index (grid/geohash) behind the detectors
  without changing their interfaces.

---

## 10. Battery optimization strategies

- **Adaptive sampling**: the `LocationProvider` should lower fix frequency when
  `MovementState.stopped`/`stationary` and raise it when driving.
- **Distance filters**: only emit a new fix after N meters of movement.
- **Pause when idle**: `pauseTracking()` when the app is backgrounded and no
  geofences are imminent; `resumeTracking()` on foreground/route start.
- **Geofence-first**: prefer OS geofencing to wake the app rather than a
  continuous stream where possible.
- **Coalesce work**: debounce downstream reactions to `LocationUpdated`.

---

## 11. Offline strategy

- Positioning continues via an offline/downloaded-park `LocationProvider`.
- `GPSCacheService` retains the last known position/context so the engine keeps
  producing a `TravelContext` during signal loss (`GpsLost`/`GpsRecovered`).
- Boundary/attraction content is loaded through the shared repositories, whose
  generic base already serves cached data when offline and refreshes on
  reconnect; a persistent cache store makes this durable across launches.
- `LocationRepository` buffers `TravelSnapshot`s locally and syncs to Supabase
  when connectivity returns.

---

## 12. Background GPS

- A background isolate / platform foreground-service hosts a real
  `LocationProvider` and feeds fixes through the exact same
  `processLocation` pipeline — the engine, events, and `TravelContext` are
  unchanged whether running foreground or background.
- Downstream consumers keep receiving `GpsEvent`s (e.g. `ApproachingDestination`)
  while the app is backgrounded, which is what lets Explorer Radio keep making
  location-aware audio decisions during a drive.
- Android Auto / Apple CarPlay attach as additional presentation surfaces that
  watch `gpsControllerProvider`; they require no engine changes.

---

## 13. Caching

- **In-memory** (`GPSCacheService`): a capped rolling buffer of
  `LocationSnapshot`s for last-known-position continuity and distance/visited
  reasoning.
- **Content** (`ParkBoundaryRepository`, `StateBoundaryRepository`, reused
  destination/park repos): the generic repository base caches results and serves
  them offline, refreshing on reconnect.
- **Persistent history** (`LocationRepository`): `TravelSnapshot`s buffered
  locally and synced to Supabase.
- Swapping any cache for a persistent store (Hive/Isar/Drift) requires no
  changes to services or the engine — they depend on the cache interfaces only.
