import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/music/models/music_metadata.dart';

/// Repository for per-song [MusicMetadata] (sync — written by import + AI
/// tagging).
class MusicMetadataRepository extends SupabaseSyncRepository<MusicMetadata> {
  MusicMetadataRepository({required super.client, super.connectivity})
      : super(
          table: SupabaseTables.musicMetadata,
          fromJson: MusicMetadata.fromJson,
          toJson: (metadata) => metadata.toJson(),
        );

  Future<MusicMetadata?> forSong(String songId) async {
    final rows = await getWhere('song_id', songId);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<MusicMetadata>> byAlbum(String albumId) =>
      getWhere('album_id', albumId);
}

final musicMetadataRepositoryProvider =
    Provider<MusicMetadataRepository>((ref) {
  return MusicMetadataRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});
