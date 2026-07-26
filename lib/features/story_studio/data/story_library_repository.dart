import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/story_studio/models/story_category.dart';
import 'package:explorer_os_mobile/features/story_studio/models/story_entry.dart';

/// Data access for the Story Library (`story_library`).
class StoryLibraryRepository {
  const StoryLibraryRepository();

  Future<List<StoryEntry>> all() async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('story_library')
          .select()
          .order('created_at', ascending: false) as List;
      return rows
          .cast<Map<String, dynamic>>()
          .map(StoryEntry.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Published, playable stories (audio + coordinates) — for GPS playback.
  Future<List<StoryEntry>> playable() async {
    final list = await all();
    return list.where((s) => s.playable).toList(growable: false);
  }

  Future<void> insert(StoryEntry s) =>
      SupabaseService.client.from('story_library').insert(s.toInsert());

  Future<void> insertMany(List<StoryEntry> stories) => SupabaseService.client
      .from('story_library')
      .insert(stories.map((s) => s.toInsert()).toList());

  Future<void> patch(String id, Map<String, dynamic> values) =>
      SupabaseService.client.from('story_library').update({
        ...values,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);

  Future<void> approve(String id) =>
      patch(id, {'approved': true, 'status': StoryStatus.approved.dbValue});

  Future<void> publish(String id, bool published) => patch(id, {
        'published': published,
        'status':
            published ? StoryStatus.completed.dbValue : StoryStatus.approved.dbValue,
      });

  Future<void> updateTranscript(String id, String transcript) =>
      patch(id, {'transcript': transcript});

  Future<void> delete(String id) =>
      SupabaseService.client.from('story_library').delete().eq('id', id);
}

final storyLibraryRepositoryProvider =
    Provider<StoryLibraryRepository>((ref) => const StoryLibraryRepository());

final storyLibraryProvider = FutureProvider<List<StoryEntry>>((ref) {
  ref.watch(storyRefreshProvider);
  return ref.watch(storyLibraryRepositoryProvider).all();
});

/// Published playable stories, loaded for GPS-triggered playback.
final playableStoriesProvider = FutureProvider<List<StoryEntry>>(
    (ref) => ref.watch(storyLibraryRepositoryProvider).playable());

class StoryRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final storyRefreshProvider =
    NotifierProvider<StoryRefresh, int>(StoryRefresh.new);
