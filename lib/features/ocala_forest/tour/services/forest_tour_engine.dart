import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/services/location_trigger_engine.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/ocala_forest/controllers/forest_experience_controller.dart'
    show kForestDefaultGeofenceMeters;
import 'package:explorer_os_mobile/features/ocala_forest/discover/services/nearest_trail_finder.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_location.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_trail.dart';
import 'package:explorer_os_mobile/features/ocala_forest/tour/models/tour_subject.dart';
import 'package:explorer_os_mobile/features/ocala_forest/tour/models/tour_type.dart';
import 'package:explorer_os_mobile/features/ocala_forest/tour/services/tour_subject_selector.dart';

/// Pure, Riverpod-free "should the tour say something new right now?"
/// engine (mirrors the existing `ForestExperienceEngine`'s shape/testing
/// approach exactly). NOT a new geofence/location system: it wraps the
/// SAME `LocationTriggerEngine` `ForestExperienceEngine` already uses for
/// arrival detection, and the SAME `nearestTrailId` helper DISCOVER
/// already uses for "which trail am I near" — this class only adds the
/// movement/time cooldown (spec §9) and subject selection on top.
class ForestTourEngine {
  ForestTourEngine({
    this.minSecondsBetweenSegments = 90,
    this.minMetersBetweenSegments = 120,
    this.trailProximityMeters = 100,
  });

  /// How long, at minimum, the guide stays quiet after speaking before
  /// considering a new segment — even if the visitor keeps moving.
  final int minSecondsBetweenSegments;

  /// How far, at minimum, the visitor must have moved since the last
  /// segment before a new one is considered — together with the time
  /// cooldown above, this is what stops the tour "talking every few feet"
  /// (spec §9).
  final double minMetersBetweenSegments;
  final double trailProximityMeters;

  final _locationTrigger = LocationTriggerEngine();
  final _selector = const TourSubjectSelector();

  DateTime? _lastSegmentAt;
  ({double lat, double lng})? _lastSegmentPosition;
  String? _lastTrailId;

  /// Feeds one GPS fix. Returns a new [TourSubject] to narrate, or null if
  /// nothing meaningfully new is due yet — callers must treat null as
  /// "stay quiet," never as an error.
  TourSubject? onLocation({
    required GPSLocation fix,
    required List<ForestLocation> locations,
    required List<ForestTrail> trails,
    required Set<String> recentlyDiscussedIds,
    TourType tourType = TourType.general,
    DateTime? now,
  }) {
    final effectiveNow = now ?? DateTime.now();

    if (_lastSegmentAt != null) {
      final elapsed = effectiveNow.difference(_lastSegmentAt!).inSeconds;
      final moved = _lastSegmentPosition == null
          ? double.infinity
          : GeoMath.distanceMeters(
              _lastSegmentPosition!.lat, _lastSegmentPosition!.lng, fix.latitude, fix.longitude);
      if (elapsed < minSecondsBetweenSegments && moved < minMetersBetweenSegments) {
        return null;
      }
    }

    final nearestTrail =
        nearestTrailId(fix.latitude, fix.longitude, trails, maxMeters: trailProximityMeters);
    final trailChanged = nearestTrail != null && nearestTrail != _lastTrailId;

    final candidates = [
      for (final l in locations)
        if (l.active)
          TriggerableLocation(
            id: l.id,
            latitude: l.latitude,
            longitude: l.longitude,
            radiusMeters: l.geofenceRadiusMeters ?? kForestDefaultGeofenceMeters,
          ),
    ];
    final events =
        _locationTrigger.evaluate(fix.latitude, fix.longitude, candidates, now: effectiveNow);
    final arrivedIds = {
      for (final e in events)
        if (e.kind == LocationTriggerKind.arrival) e.locationId,
    };

    final subject = _selector.selectForMovement(
      lat: fix.latitude,
      lng: fix.longitude,
      locations: locations,
      trails: trails,
      preferredTrailId: trailChanged ? nearestTrail : null,
      arrivedLocationIds: arrivedIds,
      recentlyDiscussedIds: recentlyDiscussedIds,
      tourType: tourType,
    );

    if (nearestTrail != null) _lastTrailId = nearestTrail;
    if (subject == null) return null;

    _lastSegmentAt = effectiveNow;
    _lastSegmentPosition = (lat: fix.latitude, lng: fix.longitude);
    return subject;
  }

  /// Used by explicit user actions (tour start, "Tell Me Something") —
  /// bypasses the cooldown/arrival gating (the visitor asked directly) but
  /// still records the result so the passive engine's cooldown/anti-repeat
  /// stays consistent with whatever was just said.
  TourSubject onDemand({
    required double lat,
    required double lng,
    required List<ForestLocation> locations,
    required List<ForestTrail> trails,
    required Set<String> recentlyDiscussedIds,
    TourType tourType = TourType.general,
    DateTime? now,
  }) {
    final nearestTrail =
        nearestTrailId(lat, lng, trails, maxMeters: trailProximityMeters);
    final subject = _selector.selectOnDemand(
      lat: lat,
      lng: lng,
      locations: locations,
      trails: trails,
      preferredTrailId: nearestTrail,
      recentlyDiscussedIds: recentlyDiscussedIds,
      tourType: tourType,
    );
    _lastSegmentAt = now ?? DateTime.now();
    _lastSegmentPosition = (lat: lat, lng: lng);
    if (nearestTrail != null) _lastTrailId = nearestTrail;
    return subject;
  }
}
