import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';

/// What kind of GPS trigger fired for a location.
enum LocationTriggerKind { arrival, departure }

/// A single fired trigger.
class LocationTriggerEvent {
  const LocationTriggerEvent(this.locationId, this.kind, this.timestamp);
  final String locationId;
  final LocationTriggerKind kind;
  final DateTime timestamp;
}

/// The minimal shape [LocationTriggerEngine] needs — decoupled from
/// `MasterLocation` so the engine stays pure/testable and reusable by any
/// future location source, not just the master `locations` table.
class TriggerableLocation {
  const TriggerableLocation({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    this.arrivalTrigger = true,
    this.departureTrigger = false,
    this.playOnce = false,
    this.cooldownSeconds,
  });

  final String id;
  final double latitude;
  final double longitude;
  final double radiusMeters;

  /// Fire when entering [radiusMeters]. Defaults to true — matches the
  /// pre-migration-0038 behavior (every location triggered on arrival).
  final bool arrivalTrigger;

  /// Fire when leaving [radiusMeters] (only meaningful after having been
  /// inside). Defaults to false — opt-in.
  final bool departureTrigger;

  /// Once true, this location never fires again after its first trigger
  /// (arrival OR departure, whichever happens first) — [cooldownSeconds] is
  /// ignored in that case.
  final bool playOnce;

  /// Minimum seconds between repeat triggers (arrival or departure share one
  /// cooldown clock per location). Null = no cooldown enforced.
  final int? cooldownSeconds;
}

class _LocationTriggerState {
  bool inside = false;
  bool everFired = false;
  DateTime? lastFiredAt;
}

/// Generic per-location GPS arrival/departure trigger engine (the fields this
/// reads — arrival_trigger, departure_trigger, play_once, cooldown_seconds —
/// were added in migration 0040).
///
/// Stateful (tracks per-location inside/outside + last-fired time, keyed by
/// [TriggerableLocation.id]) but otherwise pure: no I/O, no Riverpod, no
/// audio. That keeps it independently testable and reusable by any
/// GPS-triggered system — today's location narration, and potentially future
/// GPS-triggered songs or alerts, without duplicating this state machine.
class LocationTriggerEngine {
  final Map<String, _LocationTriggerState> _state = {};

  /// Feeds one GPS fix against every candidate location. Returns every
  /// trigger that fires for this fix — usually none or one, but a
  /// fast-moving traveler could clip several small radii in a single tick.
  List<LocationTriggerEvent> evaluate(
    double latitude,
    double longitude,
    List<TriggerableLocation> locations, {
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();
    final events = <LocationTriggerEvent>[];

    for (final loc in locations) {
      final state = _state.putIfAbsent(loc.id, () => _LocationTriggerState());
      final distance = GeoMath.distanceMeters(
        latitude,
        longitude,
        loc.latitude,
        loc.longitude,
      );
      final isInside = distance <= loc.radiusMeters;

      if (isInside && !state.inside) {
        state.inside = true;
        if (loc.arrivalTrigger && _mayFire(loc, state, t)) {
          state.everFired = true;
          state.lastFiredAt = t;
          events.add(
            LocationTriggerEvent(loc.id, LocationTriggerKind.arrival, t),
          );
        }
      } else if (!isInside && state.inside) {
        state.inside = false;
        if (loc.departureTrigger && _mayFire(loc, state, t)) {
          state.everFired = true;
          state.lastFiredAt = t;
          events.add(
            LocationTriggerEvent(loc.id, LocationTriggerKind.departure, t),
          );
        }
      }
    }
    return events;
  }

  bool _mayFire(
    TriggerableLocation loc,
    _LocationTriggerState state,
    DateTime now,
  ) {
    if (loc.playOnce && state.everFired) return false;
    final cooldown = loc.cooldownSeconds;
    if (!loc.playOnce && cooldown != null && state.lastFiredAt != null) {
      if (now.difference(state.lastFiredAt!) < Duration(seconds: cooldown)) {
        return false;
      }
    }
    return true;
  }

  /// Whether [locationId] is currently tracked as "inside" its radius.
  bool isInside(String locationId) => _state[locationId]?.inside ?? false;

  /// Clears all tracked state (e.g. starting a fresh trip/session).
  void reset() => _state.clear();
}
