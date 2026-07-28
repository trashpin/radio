import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/location_intelligence/location_intelligence.dart';
import 'package:explorer_os_mobile/features/location_intelligence/models/content_item.dart';
import 'package:explorer_os_mobile/features/maps/models/nearby_item.dart';
import 'package:explorer_os_mobile/features/maps/providers/map_places_provider.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';

/// Reads the geocoded `location_content` index. Defensive: returns [] when the
/// table doesn't exist yet (migration 0029) or Supabase is unavailable.
class LocationContentRepository {
  const LocationContentRepository();

  Future<List<ContentItem>> all() async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client.from('location_content').select()
          as List;
      return rows
          .cast<Map<String, dynamic>>()
          .map(ContentItem.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> recordPlay(String id) async {
    if (!SupabaseService.isConfigured) return;
    try {
      await SupabaseService.client
          .rpc('location_content_record_play', params: {'p_id': id});
    } catch (_) {}
  }
}

final locationContentRepositoryProvider =
    Provider<LocationContentRepository>((ref) => const LocationContentRepository());

final locationContentProvider = FutureProvider<List<ContentItem>>((ref) {
  return ref.watch(locationContentRepositoryProvider).all();
});

/// Maps an always-on map POI into a [ContentItem] so the engine can rank it even
/// before the `location_content` index is populated. (No county/city here — that
/// geocoding comes from `location_content`.)
ContentItem contentFromNearby(NearbyItem n) => ContentItem(
      id: n.id,
      title: n.name,
      category: ContentCategory.fromId(n.subcategory ?? n.category),
      subcategory: n.subcategory,
      latitude: n.latitude,
      longitude: n.longitude,
      audioUrl: n.audioUrl,
      text: n.description,
    );

/// The unified content pool the engine ranks: the geocoded index plus mapped
/// POIs (deduped by id).
final locationContentItemsProvider = Provider<List<ContentItem>>((ref) {
  final indexed = ref.watch(locationContentProvider).value ?? const [];
  final places = ref.watch(mapPlacesProvider);
  final byId = <String, ContentItem>{for (final c in indexed) c.id: c};
  for (final p in places) {
    byId.putIfAbsent(p.id, () => contentFromNearby(p));
  }
  return byId.values.toList();
});

final locationIntelligenceEngineProvider =
    Provider<LocationIntelligenceEngine>((ref) => const LocationIntelligenceEngine());

/// The live [LocationContext]: where the visitor is + everything within 20 miles,
/// best-first, derived continuously from GPS + content. Recomputes as the user
/// moves (map center) or content loads.
final locationContextProvider = Provider<LocationContext>((ref) {
  final center = ref.watch(mapCenterProvider);
  if (center == null) return LocationContext.empty;
  final travel = ref.watch(gpsControllerProvider);
  final items = ref.watch(locationContentItemsProvider);
  return ref.watch(locationIntelligenceEngineProvider).deriveContext(
        center.latitude,
        center.longitude,
        items,
        headingDegrees: travel.bearingDegrees,
        speedMps: travel.speed?.metersPerSecond ?? 0,
      );
});

/// Convenience: the current place line (e.g. "Marion County · Florida").
String? currentPlaceLabel(LocationContext ctx) {
  final parts = [ctx.city, ctx.county, ctx.state]
      .where((s) => s != null && s.trim().isNotEmpty)
      .cast<String>()
      .toList();
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Items to plot on the map: within ~20 miles of the user, with a highlight flag
/// for those within 5 miles. When the user's location is unknown, everything is
/// shown (so the map isn't empty before the first GPS fix).
class VisiblePlace {
  const VisiblePlace(this.item, this.distanceMeters, this.highlight);
  final NearbyItem item;
  final double distanceMeters;
  final bool highlight; // within 5 miles
}

const double _showRadiusM = 20 * 1609.344;
const double _highlightRadiusM = 5 * 1609.344;

final visibleMapPlacesProvider = Provider<List<VisiblePlace>>((ref) {
  final center = ref.watch(mapCenterProvider);
  final all = ref.watch(mapPlacesProvider);
  if (center == null) {
    return [for (final p in all) VisiblePlace(p, double.infinity, false)];
  }
  final out = <VisiblePlace>[];
  for (final p in all) {
    final m = _dist(center, p.latitude, p.longitude);
    if (m <= _showRadiusM) {
      out.add(VisiblePlace(p, m, m <= _highlightRadiusM));
    }
  }
  out.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
  return out;
});

double _dist(LatLng c, double lat, double lng) =>
    GeoMath.distanceMeters(c.latitude, c.longitude, lat, lng);
