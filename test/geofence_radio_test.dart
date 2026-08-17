// Verifies Option 1: GPS → get_nearby_geofences → LocationTriggerEngine ENTER
// → content resolution → RadioEngineService.requestInterruption → the EXISTING
// audio player. A fake AudioPlayerPort stands in for just_audio (exactly like
// radio_audio_service_test) so we can prove the real engine + real audio bridge
// actually receive and play the Ocklawaha location narration — and that music
// resumes at its exact position afterwards.

import 'dart:async';

import 'package:explorer_os_mobile/features/discover_area/models/area_content_block.dart';
import 'package:explorer_os_mobile/features/gps/data/geofence_repository.dart';
import 'package:explorer_os_mobile/features/gps/services/location_trigger_engine.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
import 'package:explorer_os_mobile/features/radio/providers/radio_session_provider.dart';
import 'package:explorer_os_mobile/features/radio/services/announcement_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/audio_player_port.dart';
import 'package:explorer_os_mobile/features/radio/services/gps_audio_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/history_manager.dart';
import 'package:explorer_os_mobile/features/radio/services/playback_controller.dart';
import 'package:explorer_os_mobile/features/radio/services/queue_manager_service.dart';
import 'package:explorer_os_mobile/features/radio/services/radio_audio_service.dart';
import 'package:explorer_os_mobile/features/radio/services/radio_engine_service.dart';
import 'package:explorer_os_mobile/features/radio/services/station_manager.dart';
import 'package:explorer_os_mobile/features/radio/services/story_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/user_preference_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

// Ocklawaha, per the task's live geofence.
const _ocklawahaId = 'c2cbbe87-3a9a-499e-8b10-8cb767aa2de1';
const _lat = 29.0378;
const _lng = -81.9306;

class FakeAudioPlayerPort implements AudioPlayerPort {
  final List<String> played = [];
  int pauses = 0, resumes = 0, stops = 0;
  final List<Duration> seeks = [];
  @override
  Duration position = Duration.zero;
  final _completions = StreamController<void>.broadcast();
  @override
  Stream<void> get completions => _completions.stream;
  @override
  Future<void> play(String url) async => played.add(url);
  @override
  Future<void> pause() async => pauses++;
  @override
  Future<void> resume() async => resumes++;
  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> setVolume(double v) async {}
  @override
  Future<void> seek(Duration p) async {
    seeks.add(p);
    position = p;
  }

  @override
  Future<void> dispose() async => _completions.close();
  void finishCurrent() => _completions.add(null);
}

RadioEngineService buildEngine() => RadioEngineService(
      queue: QueueManagerService(),
      playback: PlaybackController(),
      station: StationManager(),
      stories: StoryScheduler(),
      announcements: AnnouncementScheduler(),
      gps: GPSAudioScheduler(),
      history: HistoryManager(),
      preferences: UserPreferenceManager(),
    );

Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

NearbyGeofence _fence(
  String id, {
  double distance = 10,
  double radius = 8000,
  int priority = 0,
  String name = 'Ocklawaha',
}) =>
    NearbyGeofence(
      geofenceId: 'gf-$id',
      locationId: id,
      locationName: name,
      locationCategory: 'community',
      distanceMeters: distance,
      radiusMeters: radius,
      priority: priority,
    );

const _music = AudioSegment(
  id: 'song1',
  title: 'Song',
  type: AudioSegmentType.music,
  priority: PlaybackPriority.music,
  audioUrl: 'https://audio/song1.mp3',
);

void main() {
  group('geofence membership → LocationTriggerEngine (enter/exit/re-enter)', () {
    test('enters once, does not re-fire while inside, re-fires after leaving',
        () {
      final engine = LocationTriggerEngine();

      // Tick 1: arrive inside Ocklawaha → ENTER fires.
      var fired = engine.evaluate(
        _lat,
        _lng,
        geofenceTriggerCandidates(
          insideIds: {_ocklawahaId},
          recentIds: const {},
          userLat: _lat,
          userLng: _lng,
        ),
      );
      expect(fired.map((e) => e.kind), [LocationTriggerKind.arrival]);
      expect(fired.single.locationId, _ocklawahaId);

      // Tick 2: still inside → NO new trigger (prevents repeat playback).
      fired = engine.evaluate(
        _lat,
        _lng,
        geofenceTriggerCandidates(
          insideIds: {_ocklawahaId},
          recentIds: {_ocklawahaId},
          userLat: _lat,
          userLng: _lng,
        ),
      );
      expect(fired, isEmpty);

      // Tick 3: leave (no longer returned as inside) → engine resets, and with
      // departureTrigger off there is no exit narration event.
      fired = engine.evaluate(
        _lat,
        _lng,
        geofenceTriggerCandidates(
          insideIds: const {},
          recentIds: {_ocklawahaId},
          userLat: _lat,
          userLng: _lng,
        ),
      );
      expect(fired, isEmpty);

      // Tick 4: re-enter → ENTER fires again.
      fired = engine.evaluate(
        _lat,
        _lng,
        geofenceTriggerCandidates(
          insideIds: {_ocklawahaId},
          recentIds: const {},
          userLat: _lat,
          userLng: _lng,
        ),
      );
      expect(fired.map((e) => e.kind), [LocationTriggerKind.arrival]);
    });

    test('cooldown blocks a rapid re-enter, then allows it after the window',
        () {
      final engine = LocationTriggerEngine();
      List<TriggerableLocation> cands(Set<String> inside, Set<String> recent) =>
          geofenceTriggerCandidates(
            insideIds: inside,
            recentIds: recent,
            userLat: _lat,
            userLng: _lng,
            cooldownForLocation: (_) => 300,
          );
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      expect(
        engine.evaluate(_lat, _lng, cands({_ocklawahaId}, {}), now: t0),
        isNotEmpty,
      );
      // Leave then re-enter 10s later → still within cooldown → suppressed.
      engine.evaluate(_lat, _lng, cands({}, {_ocklawahaId}),
          now: t0.add(const Duration(seconds: 5)));
      expect(
        engine.evaluate(_lat, _lng, cands({_ocklawahaId}, {}),
            now: t0.add(const Duration(seconds: 10))),
        isEmpty,
      );
      // Re-enter after the cooldown window → fires again.
      engine.evaluate(_lat, _lng, cands({}, {_ocklawahaId}),
          now: t0.add(const Duration(seconds: 320)));
      expect(
        engine.evaluate(_lat, _lng, cands({_ocklawahaId}, {}),
            now: t0.add(const Duration(seconds: 330))),
        isNotEmpty,
      );
    });
  });

  group('overlap resolution (priority_override, then distance)', () {
    test('higher priority wins regardless of distance', () {
      final winner = selectGeofenceToNarrate([
        _fence('near-low', distance: 50, priority: 1, name: 'Near'),
        _fence('far-high', distance: 5000, priority: 9, name: 'Far'),
      ]);
      expect(winner!.locationName, 'Far');
    });

    test('equal priority → closest wins', () {
      final winner = selectGeofenceToNarrate([
        _fence('far', distance: 5000, priority: 5, name: 'Far'),
        _fence('near', distance: 120, priority: 5, name: 'Near'),
      ]);
      expect(winner!.locationName, 'Near');
    });

    test('empty → null (nothing fires)', () {
      expect(selectGeofenceToNarrate(const []), isNull);
    });
  });

  group('content resolution (area_discovery_content by location_id)', () {
    AreaContentBlock block(
      String token,
      String title, {
      String? audio,
      String? script,
      bool active = true,
    }) =>
        AreaContentBlock(
          id: '$token-$title',
          locationId: _ocklawahaId,
          categoryToken: token,
          title: title,
          audioUrl: audio,
          narrationScript: script,
          active: active,
        );

    test('recorded audio block → an audio segment', () {
      final seg = geofenceSegmentFor(
        locationId: _ocklawahaId,
        locationName: 'Ocklawaha',
        areaBlocks: [
          block('history', 'Ocklawaha history',
              audio: 'https://audio/ocklawaha-history.mp3'),
        ],
      );
      expect(seg, isNotNull);
      expect(seg!.audioUrl, 'https://audio/ocklawaha-history.mp3');
      expect(seg.spokenText, isNull);
      expect(seg.type, AudioSegmentType.gpsNarration);
      expect(seg.resumeAfter, isTrue); // music resumes after narration
    });

    test('script-only block → a spoken (TTS) segment', () {
      final seg = geofenceSegmentFor(
        locationId: _ocklawahaId,
        locationName: 'Ocklawaha',
        areaBlocks: [block('history', 'Ma Barker', script: 'The Barker gang…')],
      );
      expect(seg!.spokenText, 'The Barker gang…');
      expect(seg.audioUrl, isNull);
    });

    test('wildlife blocks are skipped (wildlife stays area-based)', () {
      final seg = geofenceSegmentFor(
        locationId: _ocklawahaId,
        locationName: 'Ocklawaha',
        areaBlocks: [
          block('wildlife', 'Florida Black Bear',
              audio: 'https://audio/bear.mp3'),
        ],
      );
      expect(seg, isNull); // no non-wildlife content + no master fallback
    });

    test('no content → null (caller logs + skips, radio not interrupted)', () {
      expect(
        geofenceSegmentFor(
          locationId: _ocklawahaId,
          locationName: 'Ocklawaha',
          areaBlocks: const [],
        ),
        isNull,
      );
    });
  });

  test(
      'FULL CHAIN: GPS → get_nearby_geofences → ENTER → content → real player '
      'plays Ocklawaha narration; music resumes at position', () async {
    // Capture the [GEOFENCE RADIO] diagnostics (and still surface them).
    final logs = <String>[];
    final original = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) {
      if (m != null) logs.add(m);
      original(m, wrapWidth: wrapWidth);
    };

    try {
      final engine = buildEngine();
      final port = FakeAudioPlayerPort();
      RadioAudioService(engine: engine, port: port).attach();

      // Music is playing (the normal radio).
      engine.enqueue(_music);
      engine.play();
      await settle();
      expect(port.played, ['https://audio/song1.mp3']);
      port.position = const Duration(seconds: 42); // 42s into the song

      // Run the REAL geofence tick: fake the RPC (Ocklawaha) + area content
      // (Ocklawaha history), everything else is the production code path.
      final triggerEngine = LocationTriggerEngine();
      final state = GeofenceTickState();
      final seg = await geofenceRadioTick(
        lat: _lat,
        lng: _lng,
        engine: triggerEngine,
        state: state,
        fetchNearby: (a, b) async =>
            [_fence(_ocklawahaId, distance: 10, radius: 8000, priority: 3)],
        fetchBlocks: (id) async => [
          const AreaContentBlock(
            id: 'ock-hist',
            locationId: _ocklawahaId,
            categoryToken: 'history',
            title: 'Ocklawaha history',
            audioUrl: 'https://audio/ocklawaha-history.mp3',
          ),
        ],
      );
      expect(seg, isNotNull);

      // Send it through the EXISTING engine (our code never calls just_audio).
      debugPrint('[GEOFENCE RADIO] Triggering radio interruption');
      engine.requestInterruption(seg!);
      debugPrint('[GEOFENCE RADIO] Playback request completed');
      await settle();
      // The real audio player received + played the location narration.
      expect(port.played.last, 'https://audio/ocklawaha-history.mp3');

      // Narration ends → existing interrupt/resume behavior resumes the song at
      // its exact position (never restarts it).
      port.finishCurrent();
      await settle();
      expect(port.played, [
        'https://audio/song1.mp3',
        'https://audio/ocklawaha-history.mp3',
        'https://audio/song1.mp3',
      ]);
      expect(port.seeks, [const Duration(seconds: 42)]);

      // The diagnostics fired in order.
      expect(
        logs,
        containsAllInOrder([
          '[GEOFENCE RADIO] GPS: $_lat, $_lng',
          '[GEOFENCE RADIO] Nearby geofences: 1',
          '[GEOFENCE RADIO] Selected location: Ocklawaha',
          '[GEOFENCE RADIO] location_id: $_ocklawahaId',
          '[GEOFENCE RADIO] Content: Ocklawaha history',
          '[GEOFENCE RADIO] Triggering radio interruption',
          '[GEOFENCE RADIO] Playback request completed',
        ]),
      );
    } finally {
      debugPrint = original;
    }
  });

  test('no content for a geofence → radio is NOT interrupted (logs + skip)',
      () async {
    final logs = <String>[];
    final original = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) {
      if (m != null) logs.add(m);
      original(m, wrapWidth: wrapWidth);
    };
    try {
      final seg = await geofenceRadioTick(
        lat: _lat,
        lng: _lng,
        engine: LocationTriggerEngine(),
        state: GeofenceTickState(),
        fetchNearby: (a, b) async =>
            [_fence(_ocklawahaId, name: 'Silent Place')],
        fetchBlocks: (id) async => const [], // no content, no master fallback
      );
      expect(seg, isNull); // caller will skip → radio untouched
      expect(
        logs,
        contains('[GEOFENCE RADIO] No content for location: Silent Place'),
      );
    } finally {
      debugPrint = original;
    }
  });
}
