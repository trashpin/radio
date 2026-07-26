// Proves the runtime "DJ between songs" flow end-to-end with fakes (no audio):
// songs play through a fake port, and after enough songs the engine injects a
// spoken DJ banter segment that the fake Speaker voices, then music resumes.

import 'dart:async';
import 'dart:math';

import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
import 'package:explorer_os_mobile/features/radio/services/announcement_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/audio_player_port.dart';
import 'package:explorer_os_mobile/features/radio/services/dj_banter_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/gps_audio_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/history_manager.dart';
import 'package:explorer_os_mobile/features/radio/services/playback_controller.dart';
import 'package:explorer_os_mobile/features/radio/services/queue_manager_service.dart';
import 'package:explorer_os_mobile/features/radio/services/radio_audio_service.dart';
import 'package:explorer_os_mobile/features/radio/services/radio_engine_service.dart';
import 'package:explorer_os_mobile/features/radio/services/station_manager.dart';
import 'package:explorer_os_mobile/features/radio/services/story_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/user_preference_manager.dart';
import 'package:explorer_os_mobile/shared/models/radio_station.dart';
import 'package:explorer_os_mobile/shared/models/song.dart';
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
  Future<void> dispose() async => _c.close();
  void finish() => _c.add(null);
}

/// Fake speaker: records spoken text and completes immediately.
class FakeSpeaker implements Speaker {
  final List<String> spoken = [];
  void Function()? _cb;
  @override
  set onComplete(void Function() cb) => _cb = cb;
  @override
  Future<void> speak(String text) async {
    spoken.add(text);
    _cb?.call(); // finishes right away
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
}

RadioEngineService buildEngine(DjBanterScheduler dj) => RadioEngineService(
      queue: QueueManagerService(),
      playback: PlaybackController(),
      station: StationManager(),
      stories: StoryScheduler(),
      announcements: AnnouncementScheduler(),
      gps: GPSAudioScheduler(),
      history: HistoryManager(),
      preferences: UserPreferenceManager(),
      djBanter: dj,
    );

Future<void> settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('DJ speaks between songs, then music continues', () async {
    // everyNSongs: 1 → DJ talks after every song for a deterministic test.
    final dj = DjBanterScheduler(everyNSongs: 1, rng: Random(3));
    final engine = buildEngine(dj);
    final port = FakePort();
    final speaker = FakeSpeaker();
    RadioAudioService(engine: engine, port: port, speaker: speaker).attach();

    engine.changeStation(
      const RadioStation(id: 's', name: 'Country Roads Radio'),
      songs: const [
        Song(id: '1', stationId: 's', title: 'Backroad Hymn', artist: 'The Pines', audioUrl: 'https://a/1.mp3'),
        Song(id: '2', stationId: 's', title: 'Spring Water', artist: 'The Pines', audioUrl: 'https://a/2.mp3'),
      ],
      autoPlay: true,
    );
    await settle();

    // First song is playing.
    expect(port.played, isNotEmpty);
    expect(engine.state.current?.segment.type, AudioSegmentType.music);

    // Song 1 finishes → engine injects DJ banter → speaker voices it.
    port.finish();
    await settle();

    expect(speaker.spoken, isNotEmpty,
        reason: 'DJ should speak after the song');
    expect(speaker.spoken.first.contains('{'), isFalse);
    // The banter segment is the current item while it "speaks".
    // After it completes (fake completes immediately), music plays again.
    expect(port.played.length, greaterThanOrEqualTo(2),
        reason: 'music resumes/continues after the DJ talks');
  });

  test('DJ segment carries spoken text and announcement priority', () {
    final dj = DjBanterScheduler(everyNSongs: 1, rng: Random(5));
    final seg = dj.onMusicPlayed(
      const AudioSegment(
        id: 'song:1',
        title: 'Backroad Hymn',
        type: AudioSegmentType.music,
        priority: PlaybackPriority.music,
      ),
      radioStationName: 'Country Roads Radio',
    );
    expect(seg?.spokenText, isNotNull);
    expect(seg?.audioUrl, isNull);
    expect(seg?.priority, PlaybackPriority.scheduledAnnouncement);
  });
}
