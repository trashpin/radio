# ExplorerOS — GPS Intelligence Engine Architecture

The GPS Intelligence Engine is a core system of ExplorerOS. It is **not** a GPS
location service — it understands where the user is, where they are going, what
they have visited, and turns raw fixes into a rich, published `TravelContext`
plus a stream of domain **events** the rest of the app reacts to.

It has **no map-SDK dependency** and renders/plays nothing. Positioning comes
through a swappable `LocationProvider`; consumers subscribe to events instead of
polling.

---

## 1. Overall architecture

Clean layering with dependency injection (Riverpod):

- **Provider (positioning source)** → `LocationProvider` (simulated default;
  system/Google/Apple/offline later).
- **Sub-services** each own ONE responsibility (speed, heading, bearing,
  distance, route, geofence, park/county/state detection, nearby/upcoming
  search, session, battery, cache, offline).
- **`GPSService`** orchestrates the per-fix pipeline, assembles `TravelContext`,
  maintains the session, and emits `GpsEvent`s.
- **Controller** (`GpsController`) exposes reactive state to consumers.
- **Repositories** load boundary/content data and persist location/trip history.

---

## 2. Folder structure

`lib/features/gps/`

| Folder | Responsibility |
| --- | --- |
| `models/` | Immutable value types + the published `TravelContext`. |
| `events/` | The `GpsEvent` vocabulary published on the event bus. |
| `services/` | The engine + single-responsibility sub-services. |
| `repositories/` | Boundary/content + location/trip persistence. |
| `controllers/` | `GpsController` (Riverpod `Notifier<TravelContext>`). |
| `providers/` | DI wiring (service singletons + composed engine). |
| `utils/` | `GeoMath` (great-circle distance/bearing). |
| `documentation/` | This document. |

---

## 3. Event system

`GPSService.events` is a broadcast `Stream<GpsEvent>` (`sealed` base → exhaustive
`switch`). Consumers filter for what they care about; nobody polls.

Events: `LocationUpdated`, `TravelStarted`, `TravelStopped`, `HeadingChanged`,
`SpeedChanged`, `EnteredState`/`ExitedState`, `EnteredCounty`/`ExitedCounty`,
`EnteredPark`/`ExitedPark`, `ApproachingDestination`, `ArrivedAtDestination`,
`VisitingDestination`, `LeavingDestination`, `DestinationVisited`,
`NearbyDestinationDetected`, `RouteChanged`, `GpsLost`/`GpsRecovered`,
`BackgroundTrackingStarted`/`BackgroundTrackingStopped`.

Emission is by diffing successive contexts (state/county/park/arrival/heading/
movement) plus explicit signals (`markVisited`, `reportSignalLost`,
`start/stopBackgroundTracking`, `notifyRouteChanged`).

---

## 4. Data flow

1. `LocationProvider` emits a `GPSLocation`.
2. `LocationTrackingService` forwards it to `GPSService.processLocation`.
3. Pipeline derives speed → heading/bearing → distance/route → geofence → park →
   county → state → nearby/upcoming.
4. `TravelContextService` assembles an immutable `TravelContext`; the
   `TravelSessionService` folds stats into the active session.
5. The engine caches a `LocationSnapshot`, emits the context on
   `travelContextStream`, and emits `GpsEvent`s for meaningful changes.
6. `GpsController` republishes the context; `LocationRepository`/`TravelRepository`
   persist history/sessions.

---

## 5. Service responsibilities

- **GPSService** — orchestration, context assembly, event emission, public API.
- **LocationTrackingService** — provider subscription lifecycle.
- **LocationProvider** — positioning abstraction (multi-provider seam).
- **SpeedService** — speed → movement + travel mode.
- **HeadingService** — direction of travel; **BearingService** — bearing to a target.
- **DistanceService** — distance + ETA.
- **RouteEngine** — distance travelled + next-stop progress/ETA.
- **GeofenceService** — enter/exit transition primitive.
- **ParkDetectionService** — current park + arrival state machine.
- **CountyDetectionService / StateDetectionService** — current county/state.
- **NearbySearchService / UpcomingDestinationService** — stateless spatial search
  (composed by **DestinationDetectionService**, which owns candidates + visited).
- **TravelContextService** — assembles the `TravelContext`.
- **TravelSessionService** — start/stop/reset trip sessions + cumulative stats.
- **BatteryOptimizationService** — recommends sampling cadence/distance filter.
- **GPSCacheService** — rolling snapshot buffer (offline continuity).
- **OfflineLocationService** — last-known-location fallback when offline.

### Public API (`GPSService`)
`startTracking`, `stopTracking`, `pauseTracking`, `resumeTracking`,
`start/stopBackgroundTracking`, `getCurrentLocation`, `getTravelContext`,
`getNearbyDestinations`, `getUpcomingDestinations`, `calculateHeading`,
`calculateBearing`, `calculateDistance`, `calculateETA`,
`calculateTravelDirection`, `isMoving`, `isStopped`, `isApproachingDestination`,
`isLeavingDestination`, `resetTravelSession` (+ `markVisited`,
`recommendedSamplingPolicy`, `getTravelStatistics`).

---

## 6. Provider relationships

`gpsServiceProvider` composes every sub-service provider (each a scope singleton
so they share per-fix state). `gpsControllerProvider` (`Notifier<TravelContext>`)
watches the engine's stream. `locationProviderProvider` is the single override
point to go live (swap `SimulatedLocationProvider` for a real provider).
`destinationDetectionServiceProvider` injects `nearbySearchServiceProvider` +
`upcomingDestinationServiceProvider`; `offlineLocationServiceProvider` wraps
`gpsCacheServiceProvider`.

---

## 7. Repository responsibilities

- **ParkBoundaryRepository / StateBoundaryRepository / CountyBoundaryRepository**
  — read-only geometry for detection (generic base).
- **LocationRepository** — user location history (`TravelSnapshot`, sync).
- **TravelRepository** — user trip sessions (`TravelSession`, sync).
- Destination/park **content** (`DestinationRepository`, `ParkRepository`) is
  reused from `features/destinations` — **not duplicated**; the boundary repos
  fulfill the "State/Park repository" geometry role.

---

## 8. TravelContext — the master object

Everything downstream needs, in one immutable snapshot: current GPS,
state/county/region/park/destination, nearest + upcoming + visited attractions,
heading/bearing/speed/altitude, travel & movement state, arrival status,
route progress + distance remaining, estimated arrival, cumulative statistics +
owning session, time-of-day/season (derived), and placeholders for weather and
the current radio station.

---

## 9. Battery optimization strategy

`BatteryOptimizationService` maps movement/mode → a `LocationSamplingPolicy`
(interval + distance filter): sparse when stopped/idle, frequent when driving,
moderate for walking/biking. A real `LocationProvider` adapter applies the
policy (`recommendedSamplingPolicy()`). Combine with distance filters, pausing
when backgrounded with no imminent geofence, and OS geofencing to wake the app.

---

## 10. Offline strategy

- Positioning continues via an offline/downloaded-park `LocationProvider`.
- `GPSCacheService` + `OfflineLocationService` keep a last-known position so
  `getCurrentLocation()` and reasoning degrade gracefully during signal loss
  (`GpsLost`/`GpsRecovered`).
- Boundary/attraction content loads through the shared repositories, whose base
  serves cached data offline and refreshes on reconnect.
- `LocationRepository`/`TravelRepository` buffer locally and sync to Supabase
  when connectivity returns.

---

## 11. Background GPS strategy

A background isolate / platform foreground-service hosts a real
`LocationProvider` and feeds fixes through the same `processLocation` pipeline —
engine, events, and context are identical foreground or background.
`start/stopBackgroundTracking()` emit `BackgroundTracking*` events so consumers
(e.g. Explorer Radio) know to keep running. Android Auto / CarPlay / wearables
attach as presentation surfaces watching `gpsControllerProvider` — no engine
changes.

---

## 12. Future scalability

- Real providers (system/Google/Apple/offline) behind `LocationProvider`.
- Reverse geocoding to fill `currentRoad/city/region` placeholders.
- Polygon boundaries behind the existing `contains()` contracts.
- Spatial index (grid/geohash) behind the search services for large datasets.
- Persistent cache store swap with no service/engine changes.
- Weather + radio-station population of the context placeholders.

---

## 13. Integrations

- **Explorer Radio** — subscribes to `ApproachingDestination`/`EnteredPark`/
  `ArrivedAtDestination` to interrupt/insert location & welcome audio; reads
  `TravelContext.currentRadioStationId` (set by the coordinator).
- **AI Producer** — a coordinator maps `TravelContext` → `ProducerContext`
  (`gpsLocation`, park/state, `upcomingAttraction` ← `nextAttraction`,
  time/season); the Producer returns a `PlaybackDecision`.
- **Story Engine** — reacts to arrival/enter events to unlock/queue stories for
  the current park/stop; uses `visitedStopIds` to avoid repeats.
- **Maps / Navigation** — watch `gpsControllerProvider` for position, heading,
  bearing, nearby/upcoming pins, route progress, and travelled path (cache).
- **Explorer / Destination screens** — use nearby/upcoming + distance to sort and
  badge destinations ("2 mi ahead", "visited").
