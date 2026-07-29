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

class FakePort implements AudioPlayerPort {
  final List<String> played = [];
  final _c = StreamController<void>.broadcast();
  @override
  Stream<void> get completions => _c.stream;
  @override
  Future<void> play(String url) async => played.add(url);
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> setVolume(double v) async {}
  @override
  Duration get position => Duration.zero;
  @override
  Future<void> seek(Duration p) async {}
  @override
  Future<void> dispose() async => _c.close();
  void finish() => _c.add(null);
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
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

const _song = AudioSegment(
  id: 'song:1',
  title: 'Preloaded Song',
  type: AudioSegmentType.music,
  priority: PlaybackPriority.music,
  audioUrl: 'https://audio/song.mp3',
);

const _narration = AudioSegment(
  id: 'obs:1',
  title: 'Barred Owl',
  type: AudioSegmentType.narration,
  priority: PlaybackPriority.scheduledAnnouncement,
  audioUrl: 'https://audio/narration.mp3',
  interruptible: true,
  resumeAfter: true,
);

void main() {
  test('I See Something narration interrupts the playing song', () async {
    final engine = buildEngine();
    final port = FakePort();
    RadioAudioService(engine: engine, port: port).attach();

    engine.enqueue(_song);
    engine.play();
    await settle();
    expect(port.played, ['https://audio/song.mp3']);

    // User taps a species → narration interruption.
    engine.requestInterruption(_narration);
    await settle();

    // EXPECT the narration to play next (not the song again).
    expect(port.played.last, 'https://audio/narration.mp3',
        reason: 'narration should interrupt & play, but got: ${port.played}');
  });
}
