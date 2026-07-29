import 'package:explorer_os_mobile/features/locations/location_health.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:flutter_test/flutter_test.dart';

MasterLocation _loc({
  bool active = true,
  bool hidden = false,
  List<String> audio = const [],
  List<String> images = const [],
  double? lat = 29.0,
  double? lng = -82.0,
  DateTime? updated,
}) =>
    MasterLocation(
      id: 'x${identityHashCode([active, hidden, audio, images, lat])}',
      name: 'L',
      type: LocationType.spring,
      latitude: lat,
      longitude: lng,
      active: active,
      hidden: hidden,
      audioFiles: audio,
      images: images,
      updatedAt: updated,
    );

void main() {
  group('MasterLocation.status', () {
    test('ready when active, visible, has audio', () {
      expect(_loc(audio: ['http://x/a.mp3']).status, LocationStatus.ready);
    });
    test('pending when active + visible but no audio', () {
      expect(_loc().status, LocationStatus.pending);
      expect(_loc().isPending, isTrue);
    });
    test('disabled when hidden or inactive', () {
      expect(_loc(hidden: true, audio: ['http://x/a.mp3']).status,
          LocationStatus.disabled);
      expect(_loc(active: false).status, LocationStatus.disabled);
    });
  });

  group('isBrokenAudioLink', () {
    test('empty is not broken (missing, not broken)', () {
      expect(isBrokenAudioLink(''), isFalse);
      expect(isBrokenAudioLink(null), isFalse);
    });
    test('non-http or malformed is broken', () {
      expect(isBrokenAudioLink('ftp://x/a.mp3'), isTrue);
      expect(isBrokenAudioLink('not a url'), isTrue);
    });
    test('valid https is not broken', () {
      expect(isBrokenAudioLink('https://cdn/x.mp3'), isFalse);
    });
  });

  group('computeLocationHealth', () {
    test('aggregates status + gaps', () {
      final all = [
        _loc(audio: ['https://x/1.mp3'], images: ['https://x/1.jpg'],
            updated: DateTime(2026, 1, 2)),
        _loc(audio: ['https://x/2.mp3'], updated: DateTime(2026, 3, 4)), // no image
        _loc(), // pending, no audio/image
        _loc(hidden: true), // disabled
        _loc(lat: null, lng: null), // missing coords + pending
        _loc(audio: ['ftp://bad']), // ready? has audio (non-empty) but broken
      ];
      final h = computeLocationHealth(all);
      expect(h.total, 6);
      expect(h.ready, 3); // three have non-empty audio and are visible
      expect(h.pending, 2); // no-audio visible ones
      expect(h.disabled, 1);
      expect(h.missingImages, greaterThanOrEqualTo(4));
      expect(h.missingCoordinates, 1);
      expect(h.brokenAudio, 1);
      expect(h.hidden, 1);
      expect(h.lastGenerated, DateTime(2026, 3, 4));
      expect(h.readyProgress, closeTo(3 / 6, 0.001));
    });

    test('empty input', () {
      final h = computeLocationHealth(const []);
      expect(h.total, 0);
      expect(h.readyProgress, 0);
    });
  });
}
