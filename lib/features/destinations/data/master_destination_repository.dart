import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/destinations/models/master_destination.dart';

/// Data access for the Master Destination dashboard: reads the rich
/// `destinations` table, toggles publish/priority, and launches AI jobs by
/// enqueueing rows into `generation_jobs`.
class MasterDestinationRepository {
  const MasterDestinationRepository();

  Future<List<MasterDestination>> list() async {
    if (!SupabaseService.isConfigured) return const [];
    // Order by name only on the server so the query works even before migration
    // 0020 adds the `priority` column; sort by priority client-side.
    final rows = await SupabaseService.client
        .from('destinations')
        .select()
        .order('name', ascending: true) as List;
    final items = rows
        .cast<Map<String, dynamic>>()
        .map(MasterDestination.fromJson)
        .toList();
    items.sort((a, b) {
      final byPriority = b.priority.compareTo(a.priority);
      return byPriority != 0
          ? byPriority
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return items;
  }

  Future<void> setPublished(String id, bool value) => SupabaseService.client
      .from('destinations')
      .update({'published': value}).eq('destination_id', id);

  Future<void> setPriority(String id, int value) => SupabaseService.client
      .from('destinations')
      .update({'priority': value}).eq('destination_id', id);

  /// Enqueue an AI job for [dest] and optimistically mark the matching status
  /// column `in_progress` so the dashboard reflects the launch immediately.
  ///
  /// Only columns that exist on the live `generation_jobs` table are inserted,
  /// so this works whether or not the destination_id link column is present.
  Future<void> launchJob(MasterDestination dest, DestinationAiJob job) async {
    if (!SupabaseService.isConfigured) return;
    final insert = <String, dynamic>{
      'destination': dest.name,
      'job_type': job.jobType,
      'status': 'pending',
      if (dest.type != null) 'destination_category': dest.type,
      if (dest.state != null) 'state': dest.state,
      if (dest.county != null) 'county': dest.county,
      if (dest.latitude != null) 'latitude': dest.latitude,
      if (dest.longitude != null) 'longitude': dest.longitude,
      'notes': 'Launched from Destination dashboard (${dest.code ?? dest.id}).',
    };
    await SupabaseService.client.from('generation_jobs').insert(insert);

    if (job.statusColumn != null) {
      try {
        await SupabaseService.client
            .from('destinations')
            .update({job.statusColumn!: 'in_progress'}).eq('destination_id', dest.id);
      } catch (_) {
        // Status columns require migration 0020; ignore if not yet applied.
      }
    }
  }
}

final masterDestinationRepositoryProvider =
    Provider<MasterDestinationRepository>((ref) => const MasterDestinationRepository());

/// Bumped after any write to refetch the dashboard.
class DestinationsRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final destinationsRefreshProvider =
    NotifierProvider<DestinationsRefresh, int>(DestinationsRefresh.new);

final masterDestinationsProvider =
    FutureProvider<List<MasterDestination>>((ref) {
  ref.watch(destinationsRefreshProvider);
  return ref.watch(masterDestinationRepositoryProvider).list();
});
