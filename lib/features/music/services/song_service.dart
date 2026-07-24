import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/radio/repositories/song_repository.dart';
import 'package:explorer_os_mobile/shared/models/song.dart';

/// Read operations over the song catalog (reuses the radio [SongRepository];
/// the music feature does not define a second Song).
class SongService {
  const SongService(this._repository);
  final SongRepository _repository;

  Future<List<Song>> all() => _repository.getAll();
  Future<Song?> byId(String id) => _repository.getById(id);
  Future<List<Song>> byStation(String stationId) =>
      _repository.byStation(stationId);
}

final songServiceProvider = Provider<SongService>((ref) {
  return SongService(ref.watch(songRepositoryProvider));
});
