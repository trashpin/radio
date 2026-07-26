import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:explorer_os_mobile/features/admin/presentation/song_uploader_page.dart';

/// Verifies the bulk importer's ID3 auto-extraction against real MP3 files
/// (generated with embedded ID3v2 tags + attached cover art).
void main() {
  test('extractMp3Tags reads title/artist/album + embedded cover art', () async {
    final bytes = File('test/fixtures/song_with_art.mp3').readAsBytesSync();
    final tags = await extractMp3Tags(bytes);

    expect(tags.title, 'Sunset Drive');
    expect(tags.artist, 'DJ Brittney');
    expect(tags.album, 'Ocala Sessions');
    expect(tags.artwork, isNotNull);
    expect(tags.artwork!.isNotEmpty, isTrue);
  });

  test('extractMp3Tags reads tags with no embedded artwork', () async {
    final bytes = File('test/fixtures/song_no_art.mp3').readAsBytesSync();
    final tags = await extractMp3Tags(bytes);

    expect(tags.title, 'Forest Rain');
    expect(tags.artist, 'The Pines');
    expect(tags.artwork, isNull);
  });

  test('extractMp3Tags never throws on non-MP3 bytes', () async {
    final tags =
        await extractMp3Tags(Uint8List.fromList(List<int>.generate(64, (i) => i)));
    expect(tags.title, isNull);
    expect(tags.artwork, isNull);
  });
}
