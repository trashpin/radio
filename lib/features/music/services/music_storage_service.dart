import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';

/// Uploads audio + cover art to Supabase Storage and returns public URLs.
///
/// WHY THIS EXISTS: audio/artwork BYTES belong in object storage, not the
/// database (which holds metadata + the resulting URL). This is the single seam
/// that talks to Supabase Storage, so the importers/services stay storage-
/// agnostic. Buckets: `music_audio`, `music_artwork` (create them in Supabase).
class MusicStorageService {
  const MusicStorageService(this._client);

  final SupabaseClient _client;

  static const String audioBucket = 'music_audio';
  static const String artworkBucket = 'music_artwork';

  Future<String> uploadAudio(String path, Uint8List bytes) =>
      _upload(audioBucket, path, bytes);

  Future<String> uploadArtwork(String path, Uint8List bytes) =>
      _upload(artworkBucket, path, bytes);

  Future<String> _upload(String bucket, String path, Uint8List bytes) async {
    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return _client.storage.from(bucket).getPublicUrl(path);
  }
}

final musicStorageServiceProvider = Provider<MusicStorageService>((ref) {
  return MusicStorageService(ref.watch(supabaseClientProvider));
});
