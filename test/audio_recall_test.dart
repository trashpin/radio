import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/admin/audio_recall/audio_recall.dart';

void main() {
  group('per-source mappers', () {
    test('audio_assets maps recall fields', () {
      final i = AudioInventoryItem.fromAudioAsset({
        'id': 'a1',
        'title': 'Wiregrass',
        'record_type': 'plants',
        'destination_code': 'OCALA',
        'voice_name': 'DJ Brittney',
        'duration': 34,
        'public_url': 'https://cdn/a.mp3',
        'status': 'complete',
        'play_count': 3,
        'tags': ['nature'],
      });
      expect(i.source, AudioSource.audioAssets);
      expect(i.displayTitle, 'Wiregrass');
      expect(i.voice, 'DJ Brittney');
      expect(i.playCount, 3);
      expect(i.hasFile, isTrue);
      expect(i.tags, ['nature']);
    });

    test('song maps audio_url + active status', () {
      final i = AudioInventoryItem.fromSong({
        'id': 's1',
        'title': 'On the Road Again',
        'artist': 'Willie Nelson',
        'park_code': 'ocala',
        'audio_url': 'https://cdn/s.mp3',
        'is_active': true,
        'genre': 'country',
      });
      expect(i.source, AudioSource.songs);
      expect(i.category, 'music');
      expect(i.voice, 'Willie Nelson');
      expect(i.status, 'active');
      expect(i.tags, contains('country'));
    });

    test('destination narration + story mappers', () {
      final n = AudioInventoryItem.fromDestinationNarration({
        'id': 'n1',
        'script_type': 'arrival',
        'destination_id': 'dest1',
        'duration_seconds': 40,
        'audio_url': 'https://cdn/n.mp3',
        'status': 'published',
      });
      expect(n.source, AudioSource.narration);
      expect(n.category, 'arrival');
      expect(n.durationSeconds, 40);

      final s = AudioInventoryItem.fromStory({
        'id': 'st1',
        'title': 'River of Grass',
        'published': false,
      });
      expect(s.source, AudioSource.story);
      expect(s.status, 'draft');
      expect(s.hasFile, isFalse); // no audio_url
    });
  });

  group('duplicates + search + stats', () {
    final items = [
      AudioInventoryItem.fromAudioAsset(
          {'id': 'a1', 'title': 'Deer', 'record_type': 'wildlife', 'public_url': 'https://c/x.mp3', 'play_count': 2}),
      AudioInventoryItem.fromSong(
          {'id': 's1', 'title': 'Song', 'audio_url': 'https://c/x.mp3'}), // dup url
      AudioInventoryItem.fromDestinationNarration(
          {'id': 'n1', 'script_type': 'welcome', 'destination_id': 'd'}), // no file
      AudioInventoryItem.fromStory(
          {'id': 'st1', 'title': 'Story', 'audio_url': 'https://c/y.mp3'}),
    ];

    test('duplicate detection across sources', () {
      final d = duplicateInventoryUrls(items);
      expect(d, contains('https://c/x.mp3'));
      expect(d, isNot(contains('https://c/y.mp3')));
    });

    test('search by query and source', () {
      expect(searchInventory(items, query: 'deer').length, 1);
      expect(searchInventory(items, source: AudioSource.songs).length, 1);
      expect(searchInventory(items, withFileOnly: true).length, 3);
    });

    test('stats aggregate total/withFile/orphan/duplicates/plays', () {
      final s = computeInventoryStats(items);
      expect(s.total, 4);
      expect(s.withFile, 3);
      expect(s.orphanScripts, 1);
      expect(s.duplicates, 2); // both x.mp3 rows
      expect(s.totalPlays, 2);
      expect(s.bySource[AudioSource.audioAssets], 1);
    });

    test('empty stats', () {
      expect(computeInventoryStats(const []).total, 0);
    });
  });
}
