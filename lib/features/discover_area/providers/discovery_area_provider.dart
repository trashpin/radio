import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/discover_area/models/discovery_area.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';

/// The area the traveler is currently in (or near), recomputed whenever their
/// GPS position or the location list changes. Null when they aren't inside
/// or near any area — the Discover Screen should show a "no area detected
/// here yet" state rather than stale content in that case.
final currentDiscoveryAreaProvider = Provider<DiscoveryArea?>((ref) {
  final center = ref.watch(mapCenterProvider);
  if (center == null) return null;
  final all = ref.watch(masterLocationsProvider).value ?? const [];
  return detectCurrentArea(all, center.latitude, center.longitude);
});
