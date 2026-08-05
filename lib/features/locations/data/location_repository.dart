import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/locations/data/location_narration_automation.dart';
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
      final rows =
          await SupabaseService.client
                  .from('locations')
                  .select()
                  .order('name', ascending: true)
              as List;
      return rows
          .cast<Map<String, dynamic>>()
          .map(MasterLocation.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> create(Map<String, dynamic> row) => _resilient(
    row,
    (r) => SupabaseService.client.from('locations').insert(r),
  );

  /// Same resilient insert as [create], but returns the new row's id (for a
  /// caller that needs it immediately — e.g. to queue a narration job right
  /// after creating a location). Kept separate from [create]/[_resilient] so
  /// existing callers of [create] are unaffected.
  Future<String?> createAndReturnId(Map<String, dynamic> row) async {
    var current = Map<String, dynamic>.from(row);
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        final inserted = await SupabaseService.client
            .from('locations')
            .insert(current)
            .select('id')
            .single();
        return inserted['id']?.toString();
      } on PostgrestException catch (e) {
        final m = RegExp(r"'([a-zA-Z0-9_]+)' column").firstMatch(e.message);
        final col = m?.group(1);
        if (col == null || !current.containsKey(col)) rethrow;
        current.remove(col);
      }
    }
    final inserted = await SupabaseService.client
        .from('locations')
        .insert(current)
        .select('id')
        .single();
    return inserted['id']?.toString();
  }

  Future<void> update(String id, Map<String, dynamic> fields) => _resilient(
    fields,
    (r) => SupabaseService.client.from('locations').update(r).eq('id', id),
  );

  /// Runs a write, dropping any column the DB doesn't have yet (e.g. before
  /// migration 0038) and retrying — so richer PoI fields never break editing
  /// on an un-migrated database.
  Future<void> _resilient(
    Map<String, dynamic> row,
    Future<void> Function(Map<String, dynamic>) run,
  ) async {
    final current = Map<String, dynamic>.from(row);
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        await run(current);
        return;
      } on PostgrestException catch (e) {
        final m = RegExp(r"'([a-zA-Z0-9_]+)' column").firstMatch(e.message);
        final col = m?.group(1);
        if (col == null || !current.containsKey(col)) {
          rethrow;
        }
        current.remove(col);
      }
    }
    await run(current);
  }

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
          'notes':
              'master_location:voice;id=${l.id}'
              ';code=${l.destinationCode ?? ''}',
        },
    ];
    await SupabaseService.client.from('generation_jobs').insert(rows);
    return rows.length;
  }

  /// Enqueues a single audio-generation job for [location] and returns the
  /// new job's id (for polling), or null if Supabase isn't configured.
  /// Powers the automated "generate narration on save" flow — same job shape
  /// as [enqueueMissingAudio], just for one location with its id back.
  Future<String?> enqueueAudioJob(MasterLocation location) async {
    if (!SupabaseService.isConfigured) return null;
    final row = {
      'destination': location.name,
      'job_type': 'audio',
      'status': 'pending',
      'latitude': location.latitude,
      'longitude': location.longitude,
      'county': location.county,
      'radius_m': 150,
      'progress': 0,
      'notes':
          'master_location:voice;id=${location.id}'
          ';code=${location.destinationCode ?? ''}',
    };
    final inserted = await SupabaseService.client
        .from('generation_jobs')
        .insert(row)
        .select('id')
        .single();
    return inserted['id']?.toString();
  }

  /// Enqueues AI text-content generation (short/long description + narration
  /// script) for each location that's missing copy — drained by the same
  /// narration worker (`master_location:content` note → `doLocationContent`).
  /// Imported/bare drafts get real, type-appropriate text to review; the
  /// worker fills only empty fields and never publishes. Returns how many were
  /// queued.
  Future<int> enqueueMissingContent(List<MasterLocation> locations) async {
    if (!SupabaseService.isConfigured || locations.isEmpty) return 0;
    final rows = [
      for (final l in locations)
        {
          'destination': l.name,
          'job_type': 'audio',
          'status': 'pending',
          'latitude': l.latitude,
          'longitude': l.longitude,
          'county': l.county,
          'progress': 0,
          'notes': 'master_location:content;id=${l.id}',
        },
    ];
    await SupabaseService.client.from('generation_jobs').insert(rows);
    return rows.length;
  }

  /// Enqueues a single content-generation job for [location], returning the new
  /// job id (for polling) — the text twin of [enqueueAudioJob].
  Future<String?> enqueueContentJob(MasterLocation location) async {
    if (!SupabaseService.isConfigured) return null;
    final inserted = await SupabaseService.client
        .from('generation_jobs')
        .insert({
          'destination': location.name,
          'job_type': 'audio',
          'status': 'pending',
          'latitude': location.latitude,
          'longitude': location.longitude,
          'county': location.county,
          'progress': 0,
          'notes': 'master_location:content;id=${location.id}',
        })
        .select('id')
        .single();
    return inserted['id']?.toString();
  }

  /// Asks the narration worker to drain the queue NOW, so a just-enqueued job
  /// runs immediately instead of waiting for the scheduled worker. Returns
  /// false if the `narration-worker` Edge Function isn't deployed/reachable
  /// (the scheduled worker will still pick the job up eventually).
  Future<bool> triggerNarrationWorker() async {
    if (!SupabaseService.isConfigured) return false;
    try {
      await SupabaseService.client.functions.invoke('narration-worker');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Current status/message of a queued job (for polling progress in the UI).
  /// Returns null if the job can't be found or Supabase isn't configured.
  Future<Map<String, dynamic>?> jobStatus(String jobId) async {
    if (!SupabaseService.isConfigured) return null;
    try {
      final row = await SupabaseService.client
          .from('generation_jobs')
          .select('status, message')
          .eq('id', jobId)
          .maybeSingle();
      return row;
    } catch (_) {
      return null;
    }
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
  }) => update(id, {'narration_ids': narrationIds, 'audio_files': audioFiles});

  /// Merges [loserId] into [winnerId]: moves the loser's media/narration onto
  /// the winner and deletes the loser (dedup without losing data).
  Future<void> merge(MasterLocation winner, MasterLocation loser) async {
    await update(winner.id, {
      'narration_ids': {...winner.narrationIds, ...loser.narrationIds}.toList(),
      'audio_files': {...winner.audioFiles, ...loser.audioFiles}.toList(),
      'images': {...winner.images, ...loser.images}.toList(),
      'videos': {...winner.videos, ...loser.videos}.toList(),
    });
    await delete(loser.id);
  }
}

final locationRepositoryProvider = Provider<LocationRepository>(
  (ref) => const LocationRepository(),
);

/// The automated narration flow, wired to the real repository — see
/// [LocationNarrationAutomation] for the orchestration itself.
final locationNarrationAutomationProvider =
    Provider<LocationNarrationAutomation>((ref) {
  final repo = ref.watch(locationRepositoryProvider);
  return LocationNarrationAutomation(
    enqueue: repo.enqueueAudioJob,
    triggerWorker: repo.triggerNarrationWorker,
    checkStatus: repo.jobStatus,
  );
});

final locationEngineProvider = Provider<LocationEngine>(
  (ref) => const LocationEngine(),
);

class LocationRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final locationRefreshProvider = NotifierProvider<LocationRefresh, int>(
  LocationRefresh.new,
);

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
  if (center == null) {
    debugPrint('[nearbyLocations] no center yet (GPS pending) → 0 results');
    return const [];
  }
  final all = ref.watch(masterLocationsProvider).value ?? const [];
  debugPrint('[nearbyLocations] querying LocationEngine.nearby at '
      '(${center.latitude}, ${center.longitude}) over ${all.length} '
      'master locations');
  final result = ref
      .watch(locationEngineProvider)
      .nearby(center.latitude, center.longitude, all);
  debugPrint('[nearbyLocations] engine returned ${result.length} '
      '${result.isEmpty ? '' : '(nearest: "${result.first.location.name}" '
          '${(result.first.distanceMeters / 1609.344).toStringAsFixed(2)}mi)'}');
  return result;
});
