import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/music/models/music_metadata.dart';
import 'package:explorer_os_mobile/features/music/repositories/music_metadata_repository.dart';

/// Reads/writes per-song [MusicMetadata], including the seam for future AI
/// tagging.
class MetadataService {
  const MetadataService(this._repository);
  final MusicMetadataRepository _repository;

  Future<MusicMetadata?> forSong(String songId) =>
      _repository.forSong(songId);

  Future<void> save(MusicMetadata metadata) => _repository.upsert(metadata);

  /// Applies tags to a song's metadata (creating the record if needed). Set
  /// [aiTagged] when the tags come from the AI pipeline.
  Future<void> tag(
    String metadataId,
    String songId,
    List<String> tags, {
    bool aiTagged = false,
  }) {
    return _repository.upsert(MusicMetadata(
      id: metadataId,
      songId: songId,
      tags: tags,
      aiTagged: aiTagged,
    ));
  }
}

final metadataServiceProvider = Provider<MetadataService>((ref) {
  return MetadataService(ref.watch(musicMetadataRepositoryProvider));
});
