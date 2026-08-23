import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/ocala_forest/data/forest_boundary_repository.dart';
import 'package:explorer_os_mobile/features/ocala_forest/data/forest_location_repository.dart';
import 'package:explorer_os_mobile/features/ocala_forest/data/forest_trail_repository.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_boundary.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_location.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_trail.dart';
import 'package:explorer_os_mobile/features/ocala_forest/services/forest_detection_service.dart';

/// Riverpod wiring for the isolated Ocala Forest Explorer feature.
///
/// Deliberately independent of `radio_session_provider.dart` and every
/// existing GPS/geofence attach function — this reads the SAME
/// [gpsControllerProvider] stream everything else already reads, but adds
/// no new listener to the shared session bootstrap, so nothing about
/// existing GPS/geofence behavior changes.

/// All forest boundaries (today: just Ocala National Forest). A
/// FutureProvider rather than a Notifier since this is small, static,
/// read-only reference data — matches `countyBoundariesProvider`'s own
/// shape elsewhere in the app.
final forestBoundariesProvider = FutureProvider<List<ForestBoundary>>((ref) {
  return ref.watch(forestBoundaryRepositoryProvider).getAll();
});

/// The Ocala National Forest boundary specifically (today: the only one).
final ocalaForestBoundaryProvider = FutureProvider<ForestBoundary?>((ref) async {
  final all = await ref.watch(forestBoundariesProvider.future);
  for (final b in all) {
    if (b.name.toLowerCase().contains('ocala')) return b;
  }
  return all.isEmpty ? null : all.first;
});

final forestLocationsProvider = FutureProvider<List<ForestLocation>>((ref) {
  return ref.watch(forestLocationRepositoryProvider).getAll();
});

/// Real, official USFS trail records (spec: "Import Official Ocala National
/// Forest Trail Records", migration 0050) — grouped, user-facing trails,
/// never the raw per-segment GIS records.
final forestTrailsProvider = FutureProvider<List<ForestTrail>>((ref) {
  return ref.watch(forestTrailRepositoryProvider).getAll();
});

const _forestDetection = ForestDetectionService();

/// Null while the boundary or a GPS fix isn't ready yet; otherwise whether
/// the traveler is currently inside Ocala National Forest.
final isInsideOcalaForestProvider = Provider<bool?>((ref) {
  final boundary = ref.watch(ocalaForestBoundaryProvider).value;
  final loc = ref.watch(gpsControllerProvider).location;
  if (boundary == null || loc == null) return null;
  return _forestDetection.isInside(boundary, loc.latitude, loc.longitude);
});
