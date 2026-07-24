import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/media/data/media_repository.dart';
import 'package:explorer_os_mobile/features/media/models/media_item.dart';
import 'package:explorer_os_mobile/features/stories/data/story_repository.dart';
import 'package:explorer_os_mobile/shared/models/story.dart';

/// Aggregate counts shown on the admin dashboard.
class AdminStats {
  const AdminStats({
    this.parks = 0,
    this.locations = 0,
    this.stories = 0,
    this.songs = 0,
    this.wildlife = 0,
    this.media = 0,
    this.published = 0,
    this.drafts = 0,
    this.pendingReview = 0,
    this.downloads = 0,
    this.subscribers = 0,
  });

  final int parks;
  final int locations;
  final int stories;
  final int songs;
  final int wildlife;
  final int media;
  final int published;
  final int drafts;
  final int pendingReview;
  final int downloads;
  final int subscribers;
}

/// Computes dashboard counts from Supabase. Missing tables degrade to 0 so the
/// dashboard renders against the current (partial) Base44 schema without error.
class AdminStatsService {
  const AdminStatsService(this._client);
  final SupabaseClient _client;

  Future<int> _count(String table) async {
    try {
      return await _client.from(table).count(CountOption.exact);
    } catch (_) {
      return 0;
    }
  }

  Future<int> _countPublished(String table, bool published) async {
    try {
      final rows = await _client.from(table).select('published');
      return rows
          .where((r) => (r['published'] as bool?) == published)
          .length;
    } catch (_) {
      return 0;
    }
  }

  Future<AdminStats> load() async {
    final counts = await Future.wait([
      _count('destinations'),
      _count('stops'),
      _count('stories'),
      _count('songs'),
      _count('wildlife'),
      _count('media'),
      _countPublished('destinations', true),
      _countPublished('destinations', false),
      _count('downloads'),
    ]);
    return AdminStats(
      parks: counts[0],
      locations: counts[1],
      stories: counts[2],
      songs: counts[3],
      wildlife: counts[4],
      media: counts[5],
      published: counts[6],
      drafts: counts[7],
      downloads: counts[8],
    );
  }
}

final adminStatsServiceProvider = Provider<AdminStatsService>(
  (ref) => AdminStatsService(ref.watch(supabaseClientProvider)),
);

/// Dashboard stats. Overridable in tests/preview with seeded data.
final adminStatsProvider = FutureProvider<AdminStats>(
  (ref) => ref.watch(adminStatsServiceProvider).load(),
);

/// All media items for the Media Library page (reuses [MediaRepository]).
final adminMediaProvider = FutureProvider<List<MediaItem>>(
  (ref) => ref.watch(mediaRepositoryProvider).getAll(),
);

/// All stories for the Stories page (reuses [StoryRepository]).
final adminStoriesProvider = FutureProvider<List<Story>>(
  (ref) => ref.watch(storyRepositoryProvider).getAll(),
);
