import 'package:explorer_os_mobile/features/around_me/logic/around_me_events.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_enums.dart';

/// A lightweight reference to a nearby experience for event detection.
typedef NearbyRef = ({
  String id,
  String name,
  double distanceMeters,
  bool isTrail,
});

/// Derives [AroundMeEvent]s from successive snapshots of the visitor's
/// surroundings.
///
/// This is a pure state machine (no timers, no I/O, no audio): feed it each
/// update and it returns the events that occurred since the previous one. It
/// tracks which POIs/trails the visitor is inside, the current zone, movement,
/// and GPS availability, and it de-duplicates so an experience only fires
/// `Entered*` once per continuous stay.
class AroundMeDetector {
  final Set<String> _insidePoi = {};
  final Set<String> _insideTrail = {};
  Set<String> _lastNearbyIds = const {};
  String? _lastZone;
  bool _zoneInitialized = false;
  bool? _wasMoving;
  bool? _gpsAvailable;

  /// Current POIs the visitor is inside (for the debug panel / tests).
  Set<String> get insidePoiIds => Set.unmodifiable(_insidePoi);

  List<AroundMeEvent> update({
    required DateTime now,
    required List<NearbyRef> nearby,
    required double triggerRadiusMeters,
    required MovementState movement,
    String? zone,
    bool gpsAvailable = true,
  }) {
    final events = <AroundMeEvent>[];

    // GPS availability transitions.
    if (_gpsAvailable == null) {
      _gpsAvailable = gpsAvailable;
    } else if (gpsAvailable != _gpsAvailable) {
      events.add(gpsAvailable ? GpsSignalRestored(now) : GpsSignalLost(now));
      _gpsAvailable = gpsAvailable;
    }
    // While positioning is lost, hold state and emit nothing else.
    if (!gpsAvailable) return events;

    // Nearby set changed (something appeared or dropped off).
    final ids = nearby.map((e) => e.id).toSet();
    if (!_setEquals(ids, _lastNearbyIds)) {
      events.add(NearbyExperiencesUpdated(now, nearby.length));
      _lastNearbyIds = ids;
    }

    // Which experiences are within the trigger radius right now.
    final insidePoiNow = <String>{};
    final insideTrailNow = <String>{};
    for (final n in nearby) {
      if (n.distanceMeters > triggerRadiusMeters) continue;
      (n.isTrail ? insideTrailNow : insidePoiNow).add(n.id);
    }

    // Enter events (only the first time inside a continuous stay).
    for (final n in nearby) {
      if (n.distanceMeters > triggerRadiusMeters) continue;
      if (n.isTrail) {
        if (_insideTrail.add(n.id)) events.add(EnteredTrail(now, n.id, n.name));
      } else {
        if (_insidePoi.add(n.id)) events.add(EnteredPoi(now, n.id, n.name));
      }
    }

    // Exit events (previously inside, now out of range or gone).
    final nameById = {for (final n in nearby) n.id: n.name};
    for (final id in _insidePoi.toList()) {
      if (!insidePoiNow.contains(id)) {
        _insidePoi.remove(id);
        events.add(ExitedPoi(now, id, nameById[id] ?? ''));
      }
    }
    for (final id in _insideTrail.toList()) {
      if (!insideTrailNow.contains(id)) {
        _insideTrail.remove(id);
        events.add(ExitedTrail(now, id, nameById[id] ?? ''));
      }
    }

    // Zone change (no event on the very first observation).
    if (!_zoneInitialized) {
      _lastZone = zone;
      _zoneInitialized = true;
    } else if (zone != _lastZone) {
      events.add(ZoneChanged(now, zone));
      _lastZone = zone;
    }

    // Movement transitions.
    final movingNow = movement == MovementState.moving;
    if (_wasMoving == null) {
      _wasMoving = movingNow;
    } else if (movingNow != _wasMoving) {
      events.add(movingNow ? VehicleMoving(now) : VehicleStopped(now));
      _wasMoving = movingNow;
    }

    return events;
  }

  void reset() {
    _insidePoi.clear();
    _insideTrail.clear();
    _lastNearbyIds = const {};
    _lastZone = null;
    _zoneInitialized = false;
    _wasMoving = null;
    _gpsAvailable = null;
  }

  static bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final e in a) {
      if (!b.contains(e)) return false;
    }
    return true;
  }
}
