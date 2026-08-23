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
/// approach exactly). NOT a new geofence/location system: arrivals are
/// detected by the SAME `LocationTriggerEngine` `ForestExperienceEngine`
/// already uses, and trail proximity by the SAME `nearestTrailId` helper
/// DISCOVER already uses. This class only adds: (1) recognizing a
/// genuinely NEW event (a fresh arrival or a fresh trail change — never
/// "the ranking recomputed to the same answer," spec §11: don't talk
/// constantly), (2) a time/distance cooldown on top of that, and (3)
/// deferring to [TourSubjectSelector] for WHICH subject wins once
/// something new is confirmed to have happened (so a just-arrived exact
/// geofence always outranks a merely-still-current trail, spec §4/§8).
class ForestTourEngine {
  ForestTourEngine({
    this.minSecondsBetweenSegments = 90,
    this.minMetersBetweenSegments = 120,
  });

  /// How long, at minimum, the guide stays quiet after speaking before
  /// considering a new segment — even if the visitor keeps moving.
  final int minSecondsBetweenSegments;

  /// How far, at minimum, the visitor must have moved since the last
  /// segment before a new one is considered — together with the time
  /// cooldown above, either one being satisfied is enough to allow a new
  /// segment (spec §9/§11).
  final double minMetersBetweenSegments;

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
    final hasNewArrival = events.any((e) => e.kind == LocationTriggerKind.arrival);

    final onTrailId = nearestTrailId(fix.latitude, fix.longitude, trails,
        maxMeters: TourSubjectSelector.kOnTrailMeters);
    final trailChanged = onTrailId != null && onTrailId != _lastTrailId;
    if (onTrailId != null) _lastTrailId = onTrailId;

    // Only a genuinely NEW event (a fresh arrival or a fresh trail change)
    // may trigger a segment — ambient movement that changes nothing about
    // "what's significant right here" must stay quiet (spec §9/§11).
    if (!hasNewArrival && !trailChanged) return null;

    final subject = _selector.rank(
      lat: fix.latitude,
      lng: fix.longitude,
      locations: locations,
      trails: trails,
      recentlyDiscussedIds: recentlyDiscussedIds,
      tourType: tourType,
    );
    if (subject == null) return null;

    _lastSegmentAt = effectiveNow;
    _lastSegmentPosition = (lat: fix.latitude, lng: fix.longitude);
    return subject;
  }

  /// Used by explicit user actions (the tour's first segment right after
  /// the intro, "Tell Me Something", "Next Story") — bypasses the
  /// cooldown/new-event gating (the visitor asked directly) but never
  /// returns null (spec §8 tier "general", §10). Still records the result
  /// so the passive engine's cooldown/anti-repeat/trail-tracking stays
  /// consistent with whatever was just said.
  TourSubject onDemand({
    required double lat,
    required double lng,
    required List<ForestLocation> locations,
    required List<ForestTrail> trails,
    required Set<String> recentlyDiscussedIds,
    TourType tourType = TourType.general,
    DateTime? now,
  }) {
    final subject = _selector.rankOnDemand(
      lat: lat,
      lng: lng,
      locations: locations,
      trails: trails,
      recentlyDiscussedIds: recentlyDiscussedIds,
      tourType: tourType,
    );
    _lastSegmentAt = now ?? DateTime.now();
    _lastSegmentPosition = (lat: lat, lng: lng);
    final onTrailId =
        nearestTrailId(lat, lng, trails, maxMeters: TourSubjectSelector.kOnTrailMeters);
    if (onTrailId != null) _lastTrailId = onTrailId;
    return subject;
  }
}
