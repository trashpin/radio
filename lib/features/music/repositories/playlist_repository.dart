import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/music/models/playlist.dart';

/// Repository for [Playlist]s (sync — users create/edit playlists).
class PlaylistRepository extends SupabaseSyncRepository<Playlist> {
  PlaylistRepository({required super.client, super.connectivity})
      : super(
          table: SupabaseTables.playlists,
          fromJson: Playlist.fromJson,
          toJson: (playlist) => playlist.toJson(),
        );
}

final playlistRepositoryProvider = Provider<PlaylistRepository>((ref) {
  return PlaylistRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});
