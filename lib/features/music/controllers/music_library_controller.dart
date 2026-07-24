import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/music/models/upload_job.dart';
import 'package:explorer_os_mobile/features/music/services/music_library_service.dart';

/// UI-facing controller exposing the latest bulk-import [UploadJob].
///
/// WHY THIS EXISTS: import UIs need a reactive handle on progress/result. This
/// [Notifier] runs imports through [MusicLibraryService] and publishes the
/// resulting job; browsing (songs/albums/search) uses `FutureProvider`s off the
/// same service.
class MusicLibraryController extends Notifier<UploadJob?> {
  MusicLibraryService get _service => ref.read(musicLibraryServiceProvider);

  @override
  UploadJob? build() => null;

  Future<void> importCsv(String content) async {
    state = await _service.importCsv(content);
  }

  Future<void> importZip(Uint8List zipBytes, {String? stationId}) async {
    state = await _service.importZip(zipBytes, stationId: stationId);
  }
}

final musicLibraryControllerProvider =
    NotifierProvider<MusicLibraryController, UploadJob?>(
  MusicLibraryController.new,
);
