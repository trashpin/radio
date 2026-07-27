import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/playback/audio_output.dart';
import 'package:explorer_os_mobile/features/playback/playback_manager.dart';
import 'package:explorer_os_mobile/features/playback/playback_models.dart';

/// A controllable [AudioOutput] for tests: records calls, can fail specific
/// URLs, and lets the test fire "completed" manually.
class FakeAudioOutput implements AudioOutput {
  FakeAudioOutput(this.name);

  final String name;
  final StreamController<void> _completions = StreamController<void>.broadcast();
  final List<String> calls = [];
  final List<double> volumes = [];
  final Set<String> failUrls = {};
  String? currentUrl;

  @override
  Stream<void> get completions => _completions.stream;

  @override
  Future<void> play(String url) async {
    calls.add('play:$url');
    if (failUrls.contains(url)) {
      throw Exception('load failed: $url');
    }
    currentUrl = url;
  }

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<void> stop() async {
    calls.add('stop');
    currentUrl = null;
  }

  @override
  Future<void> setVolume(double volume) async {
    calls.add('vol:${volume.toStringAsFixed(2)}');
    volumes.add(volume);
  }

  @override
  Future<void> dispose() async => _completions.close();

  void complete() => _completions.add(null);
}

PlaybackItem _music(String title, {String? url}) => PlaybackItem(
      type: PlaybackItemType.music,
      title: title,
      audioUrl: url ?? 'music://$title',
    );

PlaybackItem _narration(PlaybackItemType type, String title, {String? url}) =>
    PlaybackItem(type: type, title: title, audioUrl: url ?? '${type.name}://$title');

void main() {
  late FakeAudioOutput music;
  late FakeAudioOutput narration;
  late PlaybackManager pm;
  late List<PlaybackEvent> events;
  late StreamSubscription<PlaybackEvent> sub;

  setUp(() {
    music = FakeAudioOutput('music');
    narration = FakeAudioOutput('narration');
    pm = PlaybackManager(
      musicOutput: music,
      narrationOutput: narration,
      // Instant fades keep the tests fast and deterministic.
      fadeDuration: Duration.zero,
    );
    events = [];
    sub = pm.events.listen(events.add);
  });

  tearDown(() async {
    await sub.cancel();
    await pm.dispose();
  });

  List<PlaybackEventType> types() => events.map((e) => e.type).toList();

  group('music', () {
    test('playMusic enters PLAYING_MUSIC and emits started events', () async {
      await pm.playMusic(_music('Song A'));
      await pumpEventQueue();
      expect(pm.getCurrentState(), PlaybackState.playingMusic);
      expect(pm.getCurrentTrack()?.title, 'Song A');
      expect(music.currentUrl, 'music://Song A');
      expect(types(), contains(PlaybackEventType.musicStarted));
      expect(types(), contains(PlaybackEventType.playbackStarted));
    });

    test('pause/resume/stop transition state and channel', () async {
      await pm.playMusic(_music('Song A'));
      await pm.pauseMusic();
      expect(pm.getCurrentState(), PlaybackState.paused);
      await pm.resumeMusic();
      expect(pm.getCurrentState(), PlaybackState.playingMusic);
      await pm.stopMusic();
      expect(pm.getCurrentState(), PlaybackState.stopped);
      expect(pm.getCurrentTrack(), isNull);
    });

    test('next/previous navigate the playlist', () async {
      final a = _music('A');
      final b = _music('B');
      await pm.playMusic(a, playlist: [a, b]);
      expect(pm.getCurrentTrack()?.title, 'A');
      await pm.next();
      expect(pm.getCurrentTrack()?.title, 'B');
      await pm.previous();
      expect(pm.getCurrentTrack()?.title, 'A');
    });

    test('track completion auto-advances to the next track', () async {
      final a = _music('A');
      final b = _music('B');
      await pm.playMusic(a, playlist: [a, b]);
      music.complete();
      await pumpEventQueue();
      expect(pm.getCurrentTrack()?.title, 'B');
    });

    test('setVolume/mute change the effective music volume', () async {
      await pm.playMusic(_music('A'));
      music.volumes.clear();
      await pm.setVolume(0.5);
      expect(music.volumes.last, closeTo(0.5, 0.001));
      await pm.setMuted(true);
      expect(music.volumes.last, 0.0);
      expect(pm.muted, isTrue);
    });
  });

  group('narration ducking transition', () {
    test('narration ducks music, then music resumes on completion', () async {
      await pm.playMusic(_music('Song A'));
      await pm.playNarration(_narration(PlaybackItemType.narration, 'Intro'));
      await pumpEventQueue();

      expect(pm.getCurrentState(), PlaybackState.playingNarration);
      expect(pm.getCurrentTrack()?.title, 'Intro');
      // Music was ducked to 0 then paused.
      expect(music.volumes, contains(0.0));
      expect(music.calls, contains('pause'));
      expect(narration.currentUrl, 'narration://Intro');
      expect(types(), contains(PlaybackEventType.narrationStarted));

      narration.complete();
      await pumpEventQueue();

      expect(pm.getCurrentState(), PlaybackState.playingMusic);
      expect(music.calls, contains('resume'));
      expect(types(), contains(PlaybackEventType.narrationFinished));
    });
  });

  group('priority & queue', () {
    test('queued narrations are ordered by priority (desc)', () async {
      // A max-priority item plays so nothing interrupts it while we queue.
      await pm.playNarration(_narration(PlaybackItemType.emergency, 'E'));
      await pm.queueNarration(_narration(PlaybackItemType.route, 'route'));
      await pm.queueNarration(_narration(PlaybackItemType.safety, 'safety'));
      await pm.queueNarration(_narration(PlaybackItemType.poi, 'poi'));

      expect(pm.queue.map((e) => e.priority).toList(), [90, 70, 50]);
    });

    test('higher priority interrupts a playing narration and resumes it',
        () async {
      await pm.playMusic(_music('Song A'));
      await pm.playNarration(_narration(PlaybackItemType.poi, 'POI'));
      expect(pm.getCurrentTrack()?.title, 'POI');

      // Emergency (100) outranks POI (70): it interrupts.
      await pm.playNarration(_narration(PlaybackItemType.emergency, 'SOS'));
      expect(pm.getCurrentTrack()?.title, 'SOS');
      // POI was re-queued to resume afterwards.
      expect(pm.queue.map((e) => e.title), contains('POI'));

      narration.complete(); // SOS finishes
      await pumpEventQueue();
      expect(pm.getCurrentTrack()?.title, 'POI');

      narration.complete(); // POI finishes
      await pumpEventQueue();
      expect(pm.getCurrentState(), PlaybackState.playingMusic);
    });

    test('multiple queued narrations drain in priority order', () async {
      await pm.playNarration(_narration(PlaybackItemType.emergency, 'E'));
      await pm.queueNarration(_narration(PlaybackItemType.route, 'route'));
      await pm.queueNarration(_narration(PlaybackItemType.safety, 'safety'));

      narration.complete(); // E done -> safety (90)
      await pumpEventQueue();
      expect(pm.getCurrentTrack()?.title, 'safety');

      narration.complete(); // safety done -> route (50)
      await pumpEventQueue();
      expect(pm.getCurrentTrack()?.title, 'route');
    });

    test('clearQueue empties pending items but keeps current', () async {
      await pm.playNarration(_narration(PlaybackItemType.emergency, 'E'));
      await pm.queueNarration(_narration(PlaybackItemType.safety, 'safety'));
      expect(pm.queueLength, 1);
      await pm.clearQueue();
      expect(pm.queueLength, 0);
      expect(pm.getCurrentTrack()?.title, 'E');
    });
  });

  group('error handling', () {
    test('a failing narration emits error, does not crash, and skips on',
        () async {
      await pm.playMusic(_music('Song A'));
      await pm.playNarration(_narration(PlaybackItemType.narration, 'Good'));
      expect(pm.getCurrentTrack()?.title, 'Good');

      // A higher-priority clip whose URL fails to load.
      narration.failUrls.add('emergency://Boom');
      await pm.playNarration(
          _narration(PlaybackItemType.emergency, 'Boom', url: 'emergency://Boom'));
      await pumpEventQueue();

      expect(types(), contains(PlaybackEventType.errorOccurred));
      // The interrupted 'Good' narration resumes after the failure.
      expect(pm.getCurrentTrack()?.title, 'Good');
    });

    test('failing music with no next track resumes gracefully to error state',
        () async {
      music.failUrls.add('music://Bad');
      await pm.playMusic(_music('Bad', url: 'music://Bad'));
      await pumpEventQueue();
      expect(types(), contains(PlaybackEventType.errorOccurred));
      expect(pm.getCurrentState(), PlaybackState.error);
    });
  });

  group('snapshots', () {
    test('snapshot reflects state, queue and volume', () async {
      await pm.playMusic(_music('Song A'));
      final snap = pm.snapshot;
      expect(snap.state, PlaybackState.playingMusic);
      expect(snap.currentTrack?.title, 'Song A');
      expect(snap.musicStatus, ChannelStatus.playing);
      expect(snap.volume, 1.0);
    });

    test('new listeners are seeded with the current snapshot', () async {
      await pm.playMusic(_music('Song A'));
      final first = await pm.snapshots.first;
      expect(first.state, PlaybackState.playingMusic);
    });
  });
}
