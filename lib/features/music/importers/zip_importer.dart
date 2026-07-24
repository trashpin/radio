import 'dart:typed_data';

import 'package:archive/archive.dart';

/// An audio file extracted from a ZIP.
class ZipAudioEntry {
  const ZipAudioEntry({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
}

/// Extracts audio files from a ZIP archive's bytes.
///
/// Pure (uses the `archive` package, no I/O) so it's testable and web-safe. The
/// bytes for each entry are then handed to `MusicStorageService` for upload by
/// the [BulkImportService].
class ZIPImporter {
  const ZIPImporter();

  static const _audioExtensions = {
    '.mp3',
    '.m4a',
    '.aac',
    '.wav',
    '.ogg',
    '.flac',
  };

  List<ZipAudioEntry> extractAudio(Uint8List zipBytes) {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final entries = <ZipAudioEntry>[];
    for (final file in archive) {
      if (!file.isFile) continue;
      final lower = file.name.toLowerCase();
      if (_audioExtensions.any(lower.endsWith)) {
        entries.add(ZipAudioEntry(
          name: file.name,
          bytes: Uint8List.fromList(file.content as List<int>),
        ));
      }
    }
    return entries;
  }
}
