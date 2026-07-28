import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/admin/media_manager/models/media_asset.dart';
import 'package:explorer_os_mobile/features/destinations/content_engine/models/destination_content.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';
import 'package:explorer_os_mobile/features/maps/models/nearby_item.dart';

/// The data seam the [ContentRelationshipEngine] depends on. Keeping fetches
/// behind this interface makes the engine fully unit-testable with a fake
/// source (no live Supabase), and lets the backend change without touching the
/// relationship/aggregation logic.
abstract class ContentDataSource {
  Future<Map<String, dynamic>?> findDestination(String code);
  Future<List<MediaAsset>> media(DestinationRef d);
  Future<List<Species>> species(DestinationRef d);
  Future<List<Map<String, dynamic>>> narration(DestinationRef d);
  Future<List<Map<String, dynamic>>> stories(DestinationRef d);
  Future<List<Map<String, dynamic>>> music(DestinationRef d);
  Future<List<NearbyItem>> nearby(DestinationRef d);
  Future<List<Map<String, dynamic>>> historicalEvents(DestinationRef d);
}

/// Production [ContentDataSource] over Supabase. Every query is defensive:
/// unknown tables/columns or connectivity issues resolve to empty results
/// rather than throwing, so `loadDestinationExperience` never crashes.
class SupabaseContentDataSource implements ContentDataSource {
  const SupabaseContentDataSource();

  /// Bounding-box half-size (degrees) for "nearby" (~16 km).
  static const double _nearbyDelta = 0.15;

  Future<List<Map<String, dynamic>>> _list(
    Future<dynamic> Function() run,
  ) async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await run() as List;
      return rows.cast<Map<String, dynamic>>();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<Map<String, dynamic>?> findDestination(String code) async {
    if (!SupabaseService.isConfigured || code.trim().isEmpty) return null;
    final client = SupabaseService.client;
    // Try by destination_code, then id, then slug.
    for (final column in ['destination_code', 'destination_id', 'id', 'slug']) {
      try {
        final rows = await client
            .from('destinations')
            .select()
            .eq(column, code)
            .limit(1) as List;
        if (rows.isNotEmpty) return rows.first as Map<String, dynamic>;
      } catch (_) {
        // column may not exist — try the next.
      }
    }
    return null;
  }

  @override
  Future<List<MediaAsset>> media(DestinationRef d) async {
    final rows = await _list(() => SupabaseService.client
        .from('media_assets')
        .select()
        .eq('destination_id', d.id));
    return rows.map(MediaAsset.fromJson).toList();
  }

  @override
  Future<List<Species>> species(DestinationRef d) async {
    final rows = await _list(() => SupabaseService.client
        .from('species')
        .select()
        .eq('destination_id', d.id));
    return rows.map(Species.fromJson).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> narration(DestinationRef d) {
    return _list(() => SupabaseService.client
        .from('destination_narrations')
        .select()
        .eq('destination_id', d.id));
  }

  @override
  Future<List<Map<String, dynamic>>> stories(DestinationRef d) async {
    // story_library links via park_id — try the destination id, then its slug.
    for (final key in <String>{d.id, d.parkKey}) {
      if (key.isEmpty) continue;
      final rows = await _list(() => SupabaseService.client
          .from('story_library')
          .select()
          .eq('park_id', key));
      if (rows.isNotEmpty) return rows;
    }
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> music(DestinationRef d) {
    return _list(() => SupabaseService.client
        .from('songs')
        .select()
        .eq('park_code', d.parkKey));
  }

  @override
  Future<List<NearbyItem>> nearby(DestinationRef d) async {
    List<Map<String, dynamic>> rows = const [];
    if (d.hasCoordinates) {
      rows = await _list(() => SupabaseService.client
          .from('map_locations')
          .select()
          .gte('latitude', d.latitude! - _nearbyDelta)
          .lte('latitude', d.latitude! + _nearbyDelta)
          .gte('longitude', d.longitude! - _nearbyDelta)
          .lte('longitude', d.longitude! + _nearbyDelta)
          .limit(200));
    }
    if (rows.isEmpty) {
      rows = await _list(() => SupabaseService.client
          .from('map_locations')
          .select()
          .eq('park_code', d.parkKey)
          .limit(200));
    }
    return rows.map(NearbyItem.fromJson).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> historicalEvents(DestinationRef d) async {
    for (final entry in <(String, String)>[
      ('destination_id', d.id),
      ('destination_code', d.code),
      ('park_id', d.id),
    ]) {
      if (entry.$2.isEmpty) continue;
      final rows = await _list(() => SupabaseService.client
          .from('historical_events')
          .select()
          .eq(entry.$1, entry.$2));
      if (rows.isNotEmpty) return rows;
    }
    return const [];
  }
}
