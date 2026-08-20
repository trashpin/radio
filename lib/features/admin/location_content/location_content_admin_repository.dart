import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/location_intelligence/models/content_item.dart';

/// A named collection in the admin — a group of [ContentCategory]s that share a
/// section (Counties, Cities, Rivers, …). Backed by the unified
/// `location_content` table (category = the collection member).
enum LocationCollection {
  counties('Counties', [
    ContentCategory.countyWelcome,
    ContentCategory.countyHistory,
    ContentCategory.countyFunFacts,
    ContentCategory.countyNature,
    ContentCategory.countyAgriculture,
    ContentCategory.countyEconomy,
    ContentCategory.countyHiddenGems,
  ]),
  cities('Cities', [
    ContentCategory.cityWelcome,
    ContentCategory.cityHistory,
    ContentCategory.cityFunFacts,
    ContentCategory.cityIntro,
  ]),
  communities('Communities', [ContentCategory.communityStory]),
  rivers('Rivers', [ContentCategory.riverStory]),
  lakes('Lakes', [ContentCategory.lakeStory]),
  springs('Springs', [ContentCategory.water]),
  forests('Forests', [ContentCategory.forestStory]),
  scenicRoads('Scenic Roads', [
    ContentCategory.scenicDrive,
    ContentCategory.scenicRoad,
    ContentCategory.scenicOverlook,
  ]),
  historicSites('Historic Sites', [
    ContentCategory.historicLandmark,
    ContentCategory.historicHighway,
    ContentCategory.history,
  ]),
  parks('Parks', [
    ContentCategory.park,
    ContentCategory.arrival,
    ContentCategory.parkStory,
    ContentCategory.wildlife,
    ContentCategory.plants,
    ContentCategory.birds,
    ContentCategory.trees,
    ContentCategory.trails,
    ContentCategory.hiddenGem,
  ]),
  attractions('Attractions', [
    ContentCategory.attraction,
    ContentCategory.museum,
    ContentCategory.restaurant,
    ContentCategory.interestingFact,
    ContentCategory.welcome,
  ]);

  const LocationCollection(this.label, this.categories);
  final String label;
  final List<ContentCategory> categories;

  bool contains(ContentCategory c) => categories.contains(c);

  static LocationCollection of(ContentCategory c) {
    for (final col in LocationCollection.values) {
      if (col.contains(c)) return col;
    }
    return LocationCollection.attractions;
  }
}

/// CRUD + audio management for the `location_content` index (admin write access
/// is granted by migration 0029's RLS).
class LocationContentAdminRepository {
  const LocationContentAdminRepository();

  Future<List<ContentItem>> all() async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('location_content')
          .select()
          .order('county', ascending: true) as List;
      return rows.cast<Map<String, dynamic>>().map(ContentItem.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> create(Map<String, dynamic> row) =>
      SupabaseService.client.from('location_content').insert(row);

  Future<void> update(String id, Map<String, dynamic> fields) =>
      SupabaseService.client.from('location_content').update(fields).eq('id', id);

  Future<void> delete(String id) =>
      SupabaseService.client.from('location_content').delete().eq('id', id);

  /// Marks a row for re-voicing (the audio tool re-generates rows with null
  /// audio_url).
  Future<void> clearAudio(String id) => update(id, {'audio_url': null});

  /// Enqueues an ElevenLabs voicing job for [id], drained by the existing
  /// narration worker (same `generation_jobs` pipeline as Nearby Gems/Radio
  /// Automation — see `RadioAutomationRepository.enqueueSegmentAudio`). The
  /// worker voices `location_content.text` (falling back to the title) and
  /// sets `audio_url`. Returns false when Supabase isn't configured.
  Future<bool> enqueueContentAudio(String id, {String? voiceId}) async {
    if (!SupabaseService.isConfigured) return false;
    await SupabaseService.client.from('generation_jobs').insert({
      'destination': 'location_content:$id',
      'job_type': 'audio',
      'status': 'pending',
      'progress': 0,
      'notes': 'location_content:voice;id=$id'
          '${(voiceId ?? '').isEmpty ? '' : ';voice=$voiceId'}',
    });
    return true;
  }

  /// Asks the narration worker to drain the queue NOW so "Generate Audio"
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

  /// Reads back a row's current audio URL (to surface it in the admin as soon
  /// as generation completes). Null when absent/blank.
  Future<String?> audioUrlFor(String id) async {
    if (!SupabaseService.isConfigured) return null;
    try {
      final row = await SupabaseService.client
          .from('location_content')
          .select('audio_url')
          .eq('id', id)
          .maybeSingle();
      final u = (row?['audio_url'] as String?)?.trim();
      return (u == null || u.isEmpty) ? null : u;
    } catch (_) {
      return null;
    }
  }
}

final locationContentAdminRepositoryProvider =
    Provider<LocationContentAdminRepository>(
        (ref) => const LocationContentAdminRepository());

class LocationAdminRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final locationAdminRefreshProvider =
    NotifierProvider<LocationAdminRefresh, int>(LocationAdminRefresh.new);

final locationAdminItemsProvider = FutureProvider<List<ContentItem>>((ref) {
  ref.watch(locationAdminRefreshProvider);
  return ref.watch(locationContentAdminRepositoryProvider).all();
});

/// Per-collection counts (total + with audio) for the dashboard.
class CollectionStat {
  const CollectionStat(this.total, this.withAudio);
  final int total;
  final int withAudio;
}

final locationCollectionStatsProvider =
    Provider<Map<LocationCollection, CollectionStat>>((ref) {
  final items = ref.watch(locationAdminItemsProvider).value ?? const [];
  final total = <LocationCollection, int>{};
  final audio = <LocationCollection, int>{};
  for (final i in items) {
    final col = LocationCollection.of(i.category);
    total[col] = (total[col] ?? 0) + 1;
    if ((i.audioUrl ?? '').trim().isNotEmpty) {
      audio[col] = (audio[col] ?? 0) + 1;
    }
  }
  return {
    for (final col in LocationCollection.values)
      col: CollectionStat(total[col] ?? 0, audio[col] ?? 0),
  };
});
