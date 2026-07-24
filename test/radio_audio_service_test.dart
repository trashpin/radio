// Tests the audio adapter that turns engine playback intent into real audio.
// A fake AudioPlayerPort stands in for just_audio so we can verify the full
// loop (play → completion → advance), plus volume/mute/pause/stop — no device.

import 'dart:async';

import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
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
  int pauses = 0, resumes = 0, stops = 0;
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
}
