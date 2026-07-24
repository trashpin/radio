import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/music/models/artwork.dart';
import 'package:explorer_os_mobile/features/music/repositories/artwork_repository.dart';
import 'package:explorer_os_mobile/features/music/services/music_storage_service.dart';

/// Uploads cover art to Storage and records the resulting [Artwork].
class ArtworkService {
  const ArtworkService(this._repository, this._storage);

  final ArtworkRepository _repository;
  final MusicStorageService _storage;

  Future<List<Artwork>> all() => _repository.getAll();

  /// Uploads [bytes] to the artwork bucket and persists an [Artwork] row.
  Future<Artwork> upload(String id, String path, Uint8List bytes) async {
    final url = await _storage.uploadArtwork(path, bytes);
    final artwork = Artwork(id: id, url: url, storagePath: path);
    await _repository.upsert(artwork);
    return artwork;
  }
}

final artworkServiceProvider = Provider<ArtworkService>((ref) {
  return ArtworkService(
    ref.watch(artworkRepositoryProvider),
    ref.watch(musicStorageServiceProvider),
  );
});
