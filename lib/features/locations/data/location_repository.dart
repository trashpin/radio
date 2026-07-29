import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/locations/location_engine.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';

/// Read/write access to the master `locations` table — the single source every
/// system uses. Read-safe when Supabase isn't configured.
class LocationRepository {
  const LocationRepository();

  Future<List<MasterLocation>> all() async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('locations')
          .select()
          .order('name', ascending: true) as List;
      return rows
          .cast<Map<String, dynamic>>()
          .map(MasterLocation.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> create(Map<String, dynamic> row) =>
      SupabaseService.client.from('locations').insert(row);

  Future<void> update(String id, Map<String, dynamic> fields) =>
      SupabaseService.client.from('locations').update(fields).eq('id', id);

  Future<void> delete(String id) =>
      SupabaseService.client.from('locations').delete().eq('id', id);

  /// Enqueues an audio-generation job for every pending (needs-narration)
  /// location, drained by the audio tooling. Returns how many were queued.
  Future<int> enqueueMissingAudio(List<MasterLocation> pending) async {
    if (!SupabaseService.isConfigured || pending.isEmpty) return 0;
    final rows = [
      for (final l in pending)
        {
          'destination': l.name,
          'job_type': 'audio',
          'status': 'pending',
          'latitude': l.latitude,
          'longitude': l.longitude,
          'county': l.county,
          'radius_m': 150,
          'progress': 0,
          'notes': 'master_location:voice;id=${l.id}'
              ';code=${l.destinationCode ?? ''}',
        },
    ];
    await SupabaseService.client.from('generation_jobs').insert(rows);
    return rows.length;
  }

  /// Enqueues a Wikimedia Commons hero-image import job for every location
  /// missing a hero (drained server-side by tool/wikimedia_import.py). Returns
  /// how many were queued.
  Future<int> enqueueWikimediaImport(List<MasterLocation> missing) async {
    if (!SupabaseService.isConfigured || missing.isEmpty) return 0;
    final rows = [
      for (final l in missing)
        {
          'destination': l.name,
          'job_type': 'wikimedia_import',
          'status': 'pending',
          'latitude': l.latitude,
          'longitude': l.longitude,
          'county': l.county,
          'radius_m': 150,
          'progress': 0,
          'notes': 'wikimedia:hero;id=${l.id}',
        },
    ];
    await SupabaseService.client.from('generation_jobs').insert(rows);
    return rows.length;
  }

  /// Persists a resolved narration link onto a master location.
  Future<void> attachNarration(
    String id, {
    required List<String> narrationIds,
    required List<String> audioFiles,
  }) =>
      update(id, {'narration_ids': narrationIds, 'audio_files': audioFiles});

  /// Merges [loserId] into [winnerId]: moves the loser's media/narration onto
  /// the winner and deletes the loser (dedup without losing data).
  Future<void> merge(MasterLocation winner, MasterLocation loser) async {
    await update(winner.id, {
      'narration_ids':
          {...winner.narrationIds, ...loser.narrationIds}.toList(),
      'audio_files': {...winner.audioFiles, ...loser.audioFiles}.toList(),
      'images': {...winner.images, ...loser.images}.toList(),
      'videos': {...winner.videos, ...loser.videos}.toList(),
    });
    await delete(loser.id);
  }
}

final locationRepositoryProvider =
    Provider<LocationRepository>((ref) => const LocationRepository());

final locationEngineProvider = Provider<LocationEngine>((ref) => const LocationEngine());

class LocationRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final locationRefreshProvider =
    NotifierProvider<LocationRefresh, int>(LocationRefresh.new);

/// Every master location (the whole dataset). Cached; bump [locationRefreshProvider]
/// after a write.
final masterLocationsProvider = FutureProvider<List<MasterLocation>>((ref) {
  ref.watch(locationRefreshProvider);
  return ref.watch(locationRepositoryProvider).all();
});

/// Nearby master locations around the live map center (GPS), ranked by the
/// shared [LocationEngine]. This is what Radio / GPS / Nearby Explorer read.
final nearbyLocationsProvider = Provider<List<NearbyLocation>>((ref) {
  final center = ref.watch(mapCenterProvider);
  if (center == null) return const [];
  final all = ref.watch(masterLocationsProvider).value ?? const [];
  return ref
      .watch(locationEngineProvider)
      .nearby(center.latitude, center.longitude, all);
});
