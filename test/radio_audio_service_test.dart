// Tests the audio adapter that turns engine playback intent into real audio.
// A fake AudioPlayerPort stands in for just_audio so we can verify the full
// loop (play → completion → advance), plus volume/mute/pause/stop — no device.

import 'dart:async';

import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
import 'package:explorer_os_mobile/features/radio/services/ambient_audio_player.dart';
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
import 'package:flutter_test/flutter_test.dart';

class FakeAudioPlayerPort implements AudioPlayerPort {
  final List<String> played = [];
  final List<double> volumes = [];
  final List<Duration> seeks = [];
  int pauses = 0, resumes = 0, stops = 0;
  @override
  Duration position = Duration.zero;
  final StreamController<void> _completions = StreamController<void>.broadcast();

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
  Future<void> setVolume(double volume) async => volumes.add(volume);
  @override
  Future<void> seek(Duration p) async {
    seeks.add(p);
    position = p;
  }

  @override
  Future<void> dispose() async => _completions.close();

  void finishCurrent() => _completions.add(null);
}

/// Fake speaker: records spoken text and completes immediately (mirrors
/// dj_runtime_test.dart's FakeSpeaker).
class FakeSpeaker implements Speaker {
  final List<String> spoken = [];
  void Function()? _cb;
  @override
  set onComplete(void Function() cb) => _cb = cb;
  @override
  Future<void> speak(String text) async {
    spoken.add(text);
    _cb?.call();
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
}

class FakeAmbientPlayer implements AmbientPlayer {
  final List<String> played = [];
  int stops = 0;
  @override
  Future<void> play(String url) async => played.add(url);
  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> dispose() async {}
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

const _s1 = AudioSegment(
  id: 's1',
  title: 'One',
  type: AudioSegmentType.music,
  priority: PlaybackPriority.music,
  audioUrl: 'https://audio/s1.mp3',
);
const _s2 = AudioSegment(
  id: 's2',
  title: 'Two',
  type: AudioSegmentType.music,
  priority: PlaybackPriority.music,
  audioUrl: 'https://audio/s2.mp3',
);
const _narration = AudioSegment(
  id: 'n1',
  title: 'Nearby report',
  type: AudioSegmentType.narration,
  priority: PlaybackPriority.scheduledAnnouncement,
  audioUrl: 'https://audio/n1.mp3',
  interruptible: false,
  resumeAfter: true,
);
const _exploreWithAmbient = AudioSegment(
  id: 'e1',
  title: 'Silver Springs',
  type: AudioSegmentType.gpsNarration,
  priority: PlaybackPriority.scheduledAnnouncement,
  spokenText: 'Silver Springs is one of Florida\'s most remarkable natural landmarks.',
  tags: ['explore', 'whereYouAre'],
  interruptible: false,
  resumeAfter: true,
  ambientAudioUrl: 'https://ambient/water.mp3',
);
const _exploreNoAmbient = AudioSegment(
  id: 'e2',
  title: 'A town fact',
  type: AudioSegmentType.gpsNarration,
  priority: PlaybackPriority.scheduledAnnouncement,
  spokenText: 'A fact about this town.',
  tags: ['explore', 'whereYouAre'],
  interruptible: false,
  resumeAfter: true,
);
const _exploreMusicWithAmbientTag = AudioSegment(
  id: 'e-music',
  title: 'A song',
  type: AudioSegmentType.music,
  priority: PlaybackPriority.music,
  audioUrl: 'https://audio/song.mp3',
  tags: ['explore'],
  ambientAudioUrl: 'https://ambient/water.mp3',
);
const _nonExploreNarrationWithAmbient = AudioSegment(
  id: 'r1',
  title: 'Radio-mode GPS banter',
  type: AudioSegmentType.gpsNarration,
  priority: PlaybackPriority.scheduledAnnouncement,
  spokenText: 'You are entering Marion County.',
  interruptible: true,
  resumeAfter: true,
  ambientAudioUrl: 'https://ambient/water.mp3',
);

void main() {
  test('plays the started segment and advances on completion', () async {
    final engine = buildEngine();
    final port = FakeAudioPlayerPort();
    RadioAudioService(engine: engine, port: port).attach();

    engine.enqueue(_s1);
    engine.enqueue(_s2);
    engine.play();
    await settle();
    expect(port.played, ['https://audio/s1.mp3']);

    port.finishCurrent(); // s1 done → engine advances → s2 plays
    await settle();
    expect(port.played, ['https://audio/s1.mp3', 'https://audio/s2.mp3']);
  });

  test('volume and mute reach the player', () async {
    final engine = buildEngine();
    final port = FakeAudioPlayerPort();
    RadioAudioService(engine: engine, port: port).attach();

    engine.setVolume(0.3);
    await settle();
    expect(port.volumes.last, 0.3);

    engine.mute();
    await settle();
    expect(port.volumes.last, 0.0);
  });

  test('pause and stop reach the player', () async {
    final engine = buildEngine();
    final port = FakeAudioPlayerPort();
    RadioAudioService(engine: engine, port: port).attach();

    engine.pause();
    engine.stop();
    await settle();
    expect(port.pauses, 1);
    expect(port.stops, 1);
  });

  test('interruption resumes the song at the exact position (no restart)',
      () async {
    final engine = buildEngine();
    final port = FakeAudioPlayerPort();
    RadioAudioService(engine: engine, port: port).attach();

    engine.enqueue(_s1);
    engine.play();
    await settle();
    expect(port.played, ['https://audio/s1.mp3']);

    // Song has been playing for 45s.
    port.position = const Duration(seconds: 45);

    engine.requestInterruption(_narration); // "I See Something" / "What's Near Me"
    await settle();
    expect(port.played.last, 'https://audio/n1.mp3'); // narration plays over music

    port.finishCurrent(); // narration ends → music resumes
    await settle();
    // Song replays AND is seeked back to where it paused (not restarted at 0).
    expect(port.played, [
      'https://audio/s1.mp3',
      'https://audio/n1.mp3',
      'https://audio/s1.mp3',
    ]);
    expect(port.seeks, [const Duration(seconds: 45)]);
  });

  test('Skip during an interruption cancels it and resumes the song at position',
      () async {
    final engine = buildEngine();
    final port = FakeAudioPlayerPort();
    RadioAudioService(engine: engine, port: port).attach();

    engine.enqueue(_s1);
    engine.play();
    await settle();
    port.position = const Duration(seconds: 30);

    engine.requestInterruption(_narration);
    await settle();
    expect(port.played.last, 'https://audio/n1.mp3');

    engine.skip(); // Forward button while the report plays
    await settle();
    expect(port.played.last, 'https://audio/s1.mp3'); // back to the song
    expect(port.seeks, [const Duration(seconds: 30)]); // at the exact spot
  });

  group('ambient sound layer (Explore narration only, never under music)', () {
    test('starts the ambient bed under Explore narration that has one', () async {
      final engine = buildEngine();
      final port = FakeAudioPlayerPort();
      final ambient = FakeAmbientPlayer();
      RadioAudioService(
              engine: engine, port: port, speaker: FakeSpeaker(), ambient: ambient)
          .attach();

      engine.enqueue(_exploreWithAmbient);
      engine.play();
      await settle();
      expect(ambient.played, ['https://ambient/water.mp3']);
    });

    test('does not start ambient for Explore narration with no association',
        () async {
      final engine = buildEngine();
      final port = FakeAudioPlayerPort();
      final ambient = FakeAmbientPlayer();
      RadioAudioService(
              engine: engine, port: port, speaker: FakeSpeaker(), ambient: ambient)
          .attach();

      engine.enqueue(_exploreNoAmbient);
      engine.play();
      await settle();
      expect(ambient.played, isEmpty);
      expect(ambient.stops, greaterThan(0)); // settles to "nothing playing"
    });

    test('never starts ambient under a music segment, even if one is tagged '
        '"explore" and carries an ambientAudioUrl', () async {
      final engine = buildEngine();
      final port = FakeAudioPlayerPort();
      final ambient = FakeAmbientPlayer();
      RadioAudioService(
              engine: engine, port: port, speaker: FakeSpeaker(), ambient: ambient)
          .attach();

      engine.enqueue(_exploreMusicWithAmbientTag);
      engine.play();
      await settle();
      expect(ambient.played, isEmpty,
          reason: 'MUSIC + NARRATION = NEVER applies to ambient too');
    });

    test('never starts ambient under non-Explore narration (e.g. ordinary '
        'Radio-mode GPS banter), even if it somehow carried an '
        'ambientAudioUrl', () async {
      final engine = buildEngine();
      final port = FakeAudioPlayerPort();
      final ambient = FakeAmbientPlayer();
      RadioAudioService(
              engine: engine, port: port, speaker: FakeSpeaker(), ambient: ambient)
          .attach();

      engine.enqueue(_nonExploreNarrationWithAmbient);
      engine.play();
      await settle();
      expect(ambient.played, isEmpty);
    });

    test('ambient fades out before the next segment starts, whatever it is '
        '— never bleeds from one segment into the next', () async {
      final engine = buildEngine();
      final port = FakeAudioPlayerPort();
      final ambient = FakeAmbientPlayer();
      RadioAudioService(
              engine: engine, port: port, speaker: FakeSpeaker(), ambient: ambient)
          .attach();

      engine.enqueue(_exploreWithAmbient);
      engine.enqueue(_exploreNoAmbient);
      engine.play();
      await settle(); // FakeSpeaker completes instantly, so both segments run.

      expect(ambient.played, ['https://ambient/water.mp3'],
          reason: 'ambient only ever started once, for the segment that had '
              'one');
      expect(ambient.stops, greaterThanOrEqualTo(1),
          reason: 'faded out at (or before) the no-ambient segment, never '
              'left running underneath it');
    });

    test('PlaybackStopped stops the ambient layer too', () async {
      final engine = buildEngine();
      final port = FakeAudioPlayerPort();
      final ambient = FakeAmbientPlayer();
      RadioAudioService(
              engine: engine, port: port, speaker: FakeSpeaker(), ambient: ambient)
          .attach();

      engine.enqueue(_exploreWithAmbient);
      engine.play();
      await settle();
      expect(ambient.played, ['https://ambient/water.mp3']);

      engine.stop();
      await settle();
      expect(ambient.stops, greaterThan(0));
    });
  });
}
