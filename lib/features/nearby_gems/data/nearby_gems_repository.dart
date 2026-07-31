import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';
import 'package:explorer_os_mobile/features/nearby_gems/models/nearby_gem.dart';

/// Read/write access to the admin-curated `nearby_gems` table. Read-safe when
/// Supabase isn't configured or the table doesn't exist yet.
class NearbyGemsRepository {
  const NearbyGemsRepository();

  static const String bucket = 'media';

  Future<List<NearbyGem>> _query({bool activeOnly = false}) async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      var q = SupabaseService.client.from('nearby_gems').select();
      if (activeOnly) q = q.eq('active', true);
      final rows = await q.order('name', ascending: true) as List;
      return rows
          .cast<Map<String, dynamic>>()
          .map(NearbyGem.fromJson)
          .toList();
    } catch (_) {
      return const []; // table may not exist until migration 0034 is applied
    }
  }

  Future<List<NearbyGem>> all() => _query();
  Future<List<NearbyGem>> active() => _query(activeOnly: true);

  Future<void> create(Map<String, dynamic> row) =>
      SupabaseService.client.from('nearby_gems').insert(row);
  Future<void> update(String id, Map<String, dynamic> fields) =>
      SupabaseService.client.from('nearby_gems').update(fields).eq('id', id);
  Future<void> delete(String id) =>
      SupabaseService.client.from('nearby_gems').delete().eq('id', id);

  /// Uploads an image to the `media` bucket and returns its public URL.
  Future<String> uploadImage(Uint8List bytes, String filename,
      {String contentType = 'image/jpeg'}) async {
    final client = SupabaseService.client;
    final slug = filename.toLowerCase().replaceAll(RegExp(r'[^a-z0-9.]+'), '_');
    final path = 'nearby_gems/${DateTime.now().millisecondsSinceEpoch}_$slug';
    await client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );
    return client.storage.from(bucket).getPublicUrl(path);
  }
}

final nearbyGemsRepositoryProvider =
    Provider<NearbyGemsRepository>((ref) => const NearbyGemsRepository());

class NearbyGemsRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final nearbyGemsRefreshProvider =
    NotifierProvider<NearbyGemsRefresh, int>(NearbyGemsRefresh.new);

/// Every gem (admin list).
final allNearbyGemsProvider = FutureProvider<List<NearbyGem>>((ref) {
  ref.watch(nearbyGemsRefreshProvider);
  return ref.watch(nearbyGemsRepositoryProvider).all();
});

/// Active gems only.
final activeNearbyGemsProvider = FutureProvider<List<NearbyGem>>((ref) {
  ref.watch(nearbyGemsRefreshProvider);
  return ref.watch(nearbyGemsRepositoryProvider).active();
});

/// A gem paired with its live distance from the user.
class NearbyGemHit {
  const NearbyGemHit(this.gem, this.distanceMeters);
  final NearbyGem gem;
  final double distanceMeters;
}

/// The configured max distance for showing Nearby Gems (≈25 miles).
const double kNearbyGemsRadiusMeters = 40233.6;

/// The gems shown to the user: ACTIVE only, within the configured distance of
/// the current GPS position, sorted nearest-first. Empty until a fix exists.
final nearbyGemsForUserProvider = Provider<List<NearbyGemHit>>((ref) {
  final center = ref.watch(mapCenterProvider);
  if (center == null) return const [];
  final gems = ref.watch(activeNearbyGemsProvider).value ?? const [];
  final hits = <NearbyGemHit>[];
  for (final g in gems) {
    if (!g.hasCoordinates) continue;
    final m = GeoMath.distanceMeters(
        center.latitude, center.longitude, g.latitude!, g.longitude!);
    if (m <= kNearbyGemsRadiusMeters) hits.add(NearbyGemHit(g, m));
  }
  hits.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
  return hits;
});
