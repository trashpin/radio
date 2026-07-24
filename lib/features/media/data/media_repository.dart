import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/media/models/media_item.dart';
import 'package:explorer_os_mobile/shared/models/song.dart';

/// Read repository for Base44's `media` table.
///
/// Built on the generic [SupabaseReadRepository] (no duplicated query/cache
/// logic). Adds the audio-specific concerns Explorer Radio needs: filtering to
/// playable audio, resolving `file_url` against the public `mp3` bucket, and
/// mapping rows to [Song]s the engine can play.
class MediaRepository extends SupabaseReadRepository<MediaItem> {
  MediaRepository({
    required super.client,
    super.connectivity,
  }) : super(
          table: SupabaseTables.media,
          fromJson: MediaItem.fromJson,
        );

  /// Storage bucket that holds uploaded audio in this Supabase project.
  static const String audioBucket = 'mp3';

  /// Resolves a media `file_url` to a playable URL. Absolute URLs pass through;
  /// bare storage paths are resolved to the public URL of the [audioBucket].
  String? resolveUrl(String? fileUrl) {
    if (fileUrl == null || fileUrl.isEmpty) return null;
    if (fileUrl.startsWith('http://') || fileUrl.startsWith('https://')) {
      return fileUrl;
    }
    final path = fileUrl.startsWith('/') ? fileUrl.substring(1) : fileUrl;
    return client.storage.from(audioBucket).getPublicUrl(path);
  }

  /// Playable audio [Song]s for a destination, ordered by `sort_order`. Reads
  /// the destination's audio media and resolves each URL for playback.
  Future<List<Song>> songsForDestination(String destinationId) async {
    final rows = await getWhere('destination_id', destinationId);
    final audio = rows.where((m) => m.isAudio && m.published).toList()
      ..sort((a, b) => (a.sortOrder ?? 0).compareTo(b.sortOrder ?? 0));
    return audio
        .map((m) => m.toSong(destinationId, resolvedUrl: resolveUrl(m.fileUrl)))
        .toList(growable: false);
  }

  /// Destination ids that have at least one playable audio media row — used to
  /// surface only destinations that can actually power a radio station.
  Future<Set<String>> destinationIdsWithAudio() async {
    final rows = await getAll();
    return rows
        .where((m) => m.isAudio && m.published && m.destinationId != null)
        .map((m) => m.destinationId!)
        .toSet();
  }
}

final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  return MediaRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});
