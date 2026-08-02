import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/maps/models/driving_distance.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';
import 'package:explorer_os_mobile/features/maps/services/driving_distance_service.dart';
import 'package:explorer_os_mobile/features/nearby_gems/data/nearby_gems_repository.dart';

/// Real driving distance/ETA for the gems currently shown on the Nearby Gems
/// screen, keyed by gem id. Straight-line distance (in [NearbyGemHit], used
/// for the radius filter + ranking) is unaffected — this is purely additive,
/// for display.
///
/// Refetches only when it's actually worth another API call: the traveler has
/// moved a meaningful distance, the visible gem set changed, or the last fetch
/// is stale — never on every single GPS tick (GPS fixes can arrive multiple
/// times a second while driving).
final nearbyGemsDrivingDistanceProvider = NotifierProvider<
    NearbyGemsDrivingDistance, Map<String, DrivingDistanceResult>>(
  NearbyGemsDrivingDistance.new,
);

class NearbyGemsDrivingDistance
    extends Notifier<Map<String, DrivingDistanceResult>> {
  /// Only worth a new API call once the traveler has moved this far from
  /// where the last batch was fetched.
  static const double _refetchDistanceMeters = 300;

  /// Re-fetch anyway after this long, even if stationary (picks up any gem
  /// data changes without waiting for movement).
  static const Duration _staleAfter = Duration(minutes: 10);

  LatLng? _lastOrigin;
  Set<String> _lastIds = const {};
  DateTime? _lastFetchAt;
  bool _fetching = false;

  @override
  Map<String, DrivingDistanceResult> build() {
    ref.listen<List<NearbyGemHit>>(nearbyGemsForUserProvider, (_, hits) {
      final origin = ref.read(mapCenterProvider);
      if (origin != null) _maybeRefresh(origin, hits);
    });
    final hits = ref.read(nearbyGemsForUserProvider);
    final origin = ref.read(mapCenterProvider);
    if (origin != null) {
      // Fire-and-forget: don't block first build on a network call.
      scheduleMicrotask(() => _maybeRefresh(origin, hits));
    }
    return const {};
  }

  void _maybeRefresh(LatLng origin, List<NearbyGemHit> hits) {
    if (_fetching) return;
    final ids = hits.map((h) => h.gem.id).toSet();
    if (ids.isEmpty) return;

    final now = DateTime.now();
    final moved = _lastOrigin == null ||
        GeoMath.distanceMeters(
              _lastOrigin!.latitude,
              _lastOrigin!.longitude,
              origin.latitude,
              origin.longitude,
            ) >
            _refetchDistanceMeters;
    final idsChanged = ids.length != _lastIds.length || !ids.containsAll(_lastIds);
    final stale =
        _lastFetchAt == null || now.difference(_lastFetchAt!) > _staleAfter;

    if (!moved && !idsChanged && !stale) return;

    _lastOrigin = origin;
    _lastIds = ids;
    _lastFetchAt = now;
    unawaited(_fetch(origin, hits));
  }

  Future<void> _fetch(LatLng origin, List<NearbyGemHit> hits) async {
    _fetching = true;
    try {
      final service = ref.read(drivingDistanceServiceProvider);
      final destinations = {
        for (final h in hits)
          if (h.gem.hasCoordinates)
            h.gem.id: (lat: h.gem.latitude!, lng: h.gem.longitude!),
      };
      if (destinations.isEmpty) return;
      final result = await service.batchDrivingDistances(
        originLat: origin.latitude,
        originLng: origin.longitude,
        destinations: destinations,
      );
      if (result.isEmpty) return; // Fell back silently — keep prior state.
      state = {...state, ...result};
    } finally {
      _fetching = false;
    }
  }
}
