import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/discover_area/controllers/area_content_playback_controller.dart';
import 'package:explorer_os_mobile/features/discover_area/models/area_content_block.dart';

AreaContentBlock _block(
  String id, {
  String? audioUrl,
  String? narrationScript,
  List<String> images = const [],
}) =>
    AreaContentBlock(
      id: id,
      locationId: 'loc-1',
      categoryToken: 'history',
      title: 'Block $id',
      audioUrl: audioUrl,
      narrationScript: narrationScript,
      images: images,
    );

void main() {
  group('AreaContentBlock', () {
    test('fromJson/toWrite round-trip', () {
      final b = AreaContentBlock.fromJson({
        'id': '1',
        'location_id': 'loc-1',
        'category_token': 'history',
        'title': 'Early Settlement',
        'narration_script': 'Long ago...',
        'audio_url': 'https://audio/a.mp3',
        'images': ['https://img/a.jpg'],
        'sort_order': 2,
        'active': true,
      });
      expect(b.title, 'Early Settlement');
      expect(b.hasAudio, isTrue);
      expect(b.hasNarration, isTrue);
      expect(b.heroImage, 'https://img/a.jpg');
      expect(b.toWrite()['category_token'], 'history');
      expect(b.toWrite()['sort_order'], 2);
    });

    test('hasNarration is true from script alone, with no audio', () {
      final b = _block('1', narrationScript: 'Spoken text.');
      expect(b.hasAudio, isFalse);
      expect(b.hasNarration, isTrue);
    });

    test('hasNarration is false with neither audio nor script', () {
      final b = _block('1');
      expect(b.hasNarration, isFalse);
    });

    test('heroImage is null with no images', () {
      final b = _block('1');
      expect(b.heroImage, isNull);
    });

    test('missing fields default sensibly', () {
      final b = AreaContentBlock.fromJson({'id': '1'});
      expect(b.title, '');
      expect(b.categoryToken, '');
      expect(b.images, isEmpty);
      expect(b.sortOrder, 0);
      expect(b.active, isTrue);
    });
  });

  group('AreaContentPlaybackState', () {
    test('current is null and active is false with no blocks', () {
      const state = AreaContentPlaybackState();
      expect(state.current, isNull);
      expect(state.active, isFalse);
      expect(state.hasNext, isFalse);
    });

    test('current tracks index, hasNext reflects remaining blocks', () {
      final state = AreaContentPlaybackState(
        blocks: [_block('1'), _block('2'), _block('3')],
        index: 1,
      );
      expect(state.current?.id, '2');
      expect(state.hasNext, isTrue);
      expect(state.active, isTrue);
    });

    test('hasNext is false on the last block', () {
      final state = AreaContentPlaybackState(
        blocks: [_block('1'), _block('2')],
        index: 1,
      );
      expect(state.current?.id, '2');
      expect(state.hasNext, isFalse);
    });

    test('copyWith preserves blocks and only changes what is passed', () {
      final state = AreaContentPlaybackState(
        blocks: [_block('1'), _block('2')],
        index: 0,
        playing: true,
      );
      final next = state.copyWith(index: 1);
      expect(next.blocks, state.blocks);
      expect(next.index, 1);
      expect(next.playing, isTrue); // unchanged
    });
  });
}
