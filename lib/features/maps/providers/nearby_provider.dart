import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/locations/data/location_map_bridge.dart';
import 'package:explorer_os_mobile/features/maps/models/nearby_item.dart';

/// User-selectable search radius (meters). `Entire Park` = unbounded.
enum SearchRadius {
  ft100('100 ft', 30.48),
  ft250('250 ft', 76.2),
  ft500('500 ft', 152.4),
  mi025('0.25 mi', 402.34),
  mi05('0.5 mi', 804.67),
  mi1('1 mi', 1609.34),
  mi2('2 mi', 3218.69),
  mi5('5 mi', 8046.72),
  entirePark('Entire Park', double.infinity);

  const SearchRadius(this.label, this.meters);
  final String label;
  final double meters;
}

/// Repository for geolocated `map_locations` records.
class MapLocationRepository extends SupabaseReadRepository<NearbyItem> {
  MapLocationRepository({required super.client, super.connectivity})
      : super(table: SupabaseTables.mapLocations, fromJson: NearbyItem.fromJson);
}

final mapLocationRepositoryProvider = Provider<MapLocationRepository>((ref) {
  return MapLocationRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});

/// All geolocated records for "Around Me".
///
/// SINGLE SOURCE: prefers the master `locations` table (migration 0031) so
/// Around Me, the Map, and the Radio all read the ONE database. Falls back to
/// the legacy `map_locations` query when the master table is empty.
final mapLocationsProvider = FutureProvider<List<NearbyItem>>((ref) async {
  final master = ref.watch(masterNearbyItemsProvider);
  if (master.isNotEmpty) return master;
  try {
    return await ref.watch(mapLocationRepositoryProvider).getAll();
  } catch (_) {
    return const [];
  }
});

/// The user's current location (device GPS on hardware; a simulated center on
/// web). Null until known.
final mapCenterProvider =
    NotifierProvider<MapCenter, LatLng?>(MapCenter.new);

class MapCenter extends Notifier<LatLng?> {
  @override
  LatLng? build() => null;
  void set(LatLng value) => state = value;
}

/// The selected search radius (default 1 mile).
final searchRadiusProvider =
    NotifierProvider<SearchRadiusNotifier, SearchRadius>(
        SearchRadiusNotifier.new);

class SearchRadiusNotifier extends Notifier<SearchRadius> {
  @override
  SearchRadius build() => SearchRadius.mi1;
  void set(SearchRadius r) => state = r;
}

double _haversineMeters(LatLng a, LatLng b) {
  const earth = 6371000.0;
  final dLat = (b.latitude - a.latitude) * math.pi / 180;
  final dLng = (b.longitude - a.longitude) * math.pi / 180;
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(a.latitude * math.pi / 180) *
          math.cos(b.latitude * math.pi / 180) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return earth * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}

/// Records within the selected radius of the user, sorted nearest-first.
final nearbyItemsProvider = Provider<List<NearbyHit>>((ref) {
  final center = ref.watch(mapCenterProvider);
  final radius = ref.watch(searchRadiusProvider).meters;
  final all = ref.watch(mapLocationsProvider).value ?? const [];
  if (center == null) return const [];
  final hits = <NearbyHit>[];
  for (final item in all) {
    final m = _haversineMeters(center, LatLng(item.latitude, item.longitude));
    if (m <= radius) hits.add((item: item, meters: m));
  }
  hits.sort((a, b) => a.meters.compareTo(b.meters));
  return hits;
});

/// Distance formatted like the design (ft under ~0.19 mi, else miles).
String formatDistance(double meters) {
  final feet = meters * 3.28084;
  if (feet < 1000) return '${feet.round()} ft';
  return '${(meters / 1609.34).toStringAsFixed(1)} mi';
}
