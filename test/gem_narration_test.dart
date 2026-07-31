import 'dart:async';

import 'package:explorer_os_mobile/features/nearby_gems/models/nearby_gem.dart';
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

/// Fake audio port that records what URLs get played and lets the test signal
/// track completion (mirrors the harness in narration_interrupt_repro_test).
class _FakePort implements AudioPlayerPort {
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

RadioEngineService _buildEngine() => RadioEngineService(
  queue: QueueManagerService(),
  playback: PlaybackController(),
  station: StationManager(),
  stories: StoryScheduler(),
  announcements: AnnouncementScheduler(),
  gps: GPSAudioScheduler(),
  history: HistoryManager(),
  preferences: UserPreferenceManager(),
);

Future<void> _settle() async {
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

/// Builds the exact interruption segment GemNarrationController creates for a
/// gem that has prerecorded/generated narration audio.
AudioSegment _gemSegment(NearbyGem gem) => AudioSegment(
  id: 'gem:${gem.id}:1',
  title: gem.name,
  artist: gem.category,
  type: AudioSegmentType.narration,
  priority: PlaybackPriority.scheduledAnnouncement,
  audioUrl: gem.narrationUrl,
  interruptible: true,
  resumeAfter: true,
);

void main() {
  test('tapping a gem with audio interrupts music, then resumes it', () async {
    final engine = _buildEngine();
    final port = _FakePort();
    RadioAudioService(engine: engine, port: port).attach();

    engine.enqueue(_song);
    engine.play();
    await _settle();
    expect(port.played, ['https://audio/song.mp3']);

    // Traveler taps a Local Gem that has narration audio.
    const gem = NearbyGem(
      id: 'ivy',
      name: 'Ivy House',
      category: 'Restaurant',
      narrationUrl: 'https://audio/ivy.mp3',
    );
    engine.requestInterruption(_gemSegment(gem));
    await _settle();
    expect(
      port.played.last,
      'https://audio/ivy.mp3',
      reason: 'gem narration should interrupt the song, got: ${port.played}',
    );

    // When the gem story ends, the music resumes (never restarts from a report).
    port.finish();
    await _settle();
    expect(
      port.played.last,
      'https://audio/song.mp3',
      reason: 'music should resume after the gem story ends',
    );
  });
}
