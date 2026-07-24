import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/music/models/album.dart';

/// Read repository for [Album]s.
class AlbumRepository extends SupabaseReadRepository<Album> {
  AlbumRepository({required super.client, super.connectivity})
      : super(table: SupabaseTables.albums, fromJson: Album.fromJson);
}

final albumRepositoryProvider = Provider<AlbumRepository>((ref) {
  return AlbumRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});
