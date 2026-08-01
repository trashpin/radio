import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FileOptions, PostgrestException;

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
      return rows.cast<Map<String, dynamic>>().map(NearbyGem.fromJson).toList();
    } catch (_) {
      return const []; // table may not exist until migration 0034 is applied
    }
  }

  Future<List<NearbyGem>> all() => _query();
  Future<List<NearbyGem>> active() => _query(activeOnly: true);

  Future<void> create(Map<String, dynamic> row) => _resilient(
    row,
    (r) => SupabaseService.client.from('nearby_gems').insert(r),
  );
  Future<void> update(String id, Map<String, dynamic> fields) => _resilient(
    fields,
    (r) => SupabaseService.client.from('nearby_gems').update(r).eq('id', id),
  );
  Future<void> delete(String id) =>
      SupabaseService.client.from('nearby_gems').delete().eq('id', id);

  /// Runs a write, and if it fails only because a column isn't in the schema
  /// yet (e.g. migration 0035/0037 not applied), transparently drops that
  /// column and retries — so gem editing never breaks before newer columns
  /// exist. Handles several missing columns by retrying (bounded).
  Future<void> _resilient(
    Map<String, dynamic> row,
    Future<void> Function(Map<String, dynamic>) run,
  ) async {
    var current = Map<String, dynamic>.from(row);
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        await run(current);
        return;
      } on PostgrestException catch (e) {
        final col = _missingColumn(e.message);
        if (col == null || !current.containsKey(col)) {
          rethrow;
        }
        current.remove(col);
      }
    }
    // Last resort — try once more so a real error surfaces to the caller.
    await run(current);
  }

  /// Extracts a missing/unknown column name from a PostgREST schema error like
  /// `Could not find the 'featured' column of 'nearby_gems' in the schema cache`.
  static String? _missingColumn(String message) {
    final m = RegExp(r"'([a-zA-Z0-9_]+)' column").firstMatch(message);
    return m?.group(1);
  }

  /// Enqueues an ElevenLabs narration-generation job for a gem, drained by the
  /// existing narration worker (same pipeline as master-location audio). The
  /// worker voices the gem's script/Long Description and sets `narration_url`.
  /// Returns false when Supabase isn't configured.
  Future<bool> enqueueGemAudio(NearbyGem gem, {String? voiceId}) async {
    if (!SupabaseService.isConfigured) return false;
    await SupabaseService.client.from('generation_jobs').insert({
      'destination': gem.name,
      'job_type': 'audio',
      'status': 'pending',
      'latitude': gem.latitude,
      'longitude': gem.longitude,
      'radius_m': 150,
      'progress': 0,
      'notes':
          'nearby_gem:voice;id=${gem.id}'
          '${(voiceId ?? '').isEmpty ? '' : ';voice=$voiceId'}',
    });
    return true;
  }

  /// Asks the narration worker to drain the queue NOW so "Generate Narration"
  /// produces audio immediately instead of waiting for the scheduled worker.
  /// Works only if the `narration-worker` Edge Function is deployed; returns
  /// false otherwise (the scheduled GitHub worker still processes the job).
  Future<bool> triggerNarrationWorker() async {
    if (!SupabaseService.isConfigured) return false;
    try {
      await SupabaseService.client.functions.invoke('narration-worker');
      return true;
    } catch (_) {
      return false; // not deployed / unreachable — scheduled worker will run
    }
  }

  /// Reads back a gem's current narration audio URL (to surface it in the admin
  /// as soon as generation completes). Null when absent/blank.
  Future<String?> narrationUrlFor(String id) async {
    if (!SupabaseService.isConfigured) return null;
    try {
      final row = await SupabaseService.client
          .from('nearby_gems')
          .select('narration_url')
          .eq('id', id)
          .maybeSingle();
      final u = (row?['narration_url'] as String?)?.trim();
      return (u == null || u.isEmpty) ? null : u;
    } catch (_) {
      return null;
    }
  }

  /// Uploads an image to the `media` bucket and returns its public URL.
  Future<String> uploadImage(
    Uint8List bytes,
    String filename, {
    String contentType = 'image/jpeg',
  }) async {
    final client = SupabaseService.client;
    final slug = filename.toLowerCase().replaceAll(RegExp(r'[^a-z0-9.]+'), '_');
    final path = 'nearby_gems/${DateTime.now().millisecondsSinceEpoch}_$slug';
    await client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );
    return client.storage.from(bucket).getPublicUrl(path);
  }
}

final nearbyGemsRepositoryProvider = Provider<NearbyGemsRepository>(
  (ref) => const NearbyGemsRepository(),
);

class NearbyGemsRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final nearbyGemsRefreshProvider = NotifierProvider<NearbyGemsRefresh, int>(
  NearbyGemsRefresh.new,
);

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

/// Selectable Nearby Gems radii (meters): 5 miles (default) or 10 miles.
const double kGemsRadius5Mi = 8046.72;
const double kGemsRadius10Mi = 16093.44;

/// The traveler-selectable Nearby Gems search radius. Defaults to 5 miles;
/// the Local Gems screen can toggle to 10. The user provider watches this, so
/// the list updates automatically as the radius (or GPS position) changes.
class NearbyGemsRadius extends Notifier<double> {
  @override
  double build() => kGemsRadius5Mi;
  void set(double meters) => state = meters;
  void toggle() =>
      state = state <= kGemsRadius5Mi ? kGemsRadius10Mi : kGemsRadius5Mi;
}

final nearbyGemsRadiusProvider = NotifierProvider<NearbyGemsRadius, double>(
  NearbyGemsRadius.new,
);

/// Composite discovery ranking: featured first, then editorial priority, then
/// popularity, then nearest. Distance filtering happens before this. Pure, so
/// it's unit-testable.
List<NearbyGemHit> rankNearbyGems(List<NearbyGemHit> hits) {
  final out = [...hits];
  out.sort((a, b) {
    final af = a.gem.featured ? 1 : 0, bf = b.gem.featured ? 1 : 0;
    if (af != bf) return bf - af;
    if (a.gem.priority != b.gem.priority) {
      return b.gem.priority - a.gem.priority;
    }
    if (a.gem.popularity != b.gem.popularity) {
      return b.gem.popularity - a.gem.popularity;
    }
    return a.distanceMeters.compareTo(b.distanceMeters);
  });
  return out;
}

/// The gems shown to the user: ACTIVE only, within the selected radius of the
/// current GPS position, ranked by featured/priority/popularity/distance.
/// Recomputes automatically as GPS position or radius changes (gems that fall
/// out of range drop off; newly in-range gems appear) — no manual refresh.
final nearbyGemsForUserProvider = Provider<List<NearbyGemHit>>((ref) {
  final center = ref.watch(mapCenterProvider);
  if (center == null) return const [];
  final radius = ref.watch(nearbyGemsRadiusProvider);
  final gems = ref.watch(activeNearbyGemsProvider).value ?? const [];
  final hits = <NearbyGemHit>[];
  for (final g in gems) {
    if (!g.hasCoordinates) continue;
    final m = GeoMath.distanceMeters(
      center.latitude,
      center.longitude,
      g.latitude!,
      g.longitude!,
    );
    if (m <= radius) hits.add(NearbyGemHit(g, m));
  }
  return rankNearbyGems(hits);
});
