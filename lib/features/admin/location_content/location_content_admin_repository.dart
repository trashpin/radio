import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/content_generator/models/content_models.dart';
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

  /// Enqueues a bulk audio-generation job for a county (drained by the audio
  /// tooling), consistent with the Audio Production queue.
  Future<void> enqueueAudioJob(String county) {
    final job = GenerationJob(
      id: '',
      destination: county,
      jobType: JobType.audio,
      status: JobStatus.pending,
      notes: 'location_content:voice;county=$county',
    );
    return SupabaseService.client.from('generation_jobs').insert(job.toInsert());
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
