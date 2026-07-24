import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/music/models/artwork.dart';

/// Repository for [Artwork] records (sync — created when cover art is uploaded).
class ArtworkRepository extends SupabaseSyncRepository<Artwork> {
  ArtworkRepository({required super.client, super.connectivity})
      : super(
          table: SupabaseTables.artworks,
          fromJson: Artwork.fromJson,
          toJson: (artwork) => artwork.toJson(),
        );
}

final artworkRepositoryProvider = Provider<ArtworkRepository>((ref) {
  return ArtworkRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});
