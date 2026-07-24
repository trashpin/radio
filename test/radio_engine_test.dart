// Unit tests for the Explorer Radio decision engine.
//
// The engine is pure decision logic (no audio), so it can be driven entirely
// offline: we load a station, start it, and simulate the audio layer reporting
// completions / external interruptions, asserting WHAT the engine decides.

import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
import 'package:explorer_os_mobile/features/radio/services/announcement_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/gps_audio_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/history_manager.dart';
import 'package:explorer_os_mobile/features/radio/services/playback_controller.dart';
import 'package:explorer_os_mobile/features/radio/services/queue_manager_service.dart';
import 'package:explorer_os_mobile/features/radio/services/radio_engine_service.dart';
import 'package:explorer_os_mobile/features/radio/services/station_manager.dart';
import 'package:explorer_os_mobile/features/radio/services/story_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/user_preference_manager.dart';
import 'package:explorer_os_mobile/shared/models/narration.dart';
import 'package:explorer_os_mobile/shared/models/radio_station.dart';
import 'package:explorer_os_mobile/shared/models/song.dart';
import 'package:flutter_test/flutter_test.dart';

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

const _emergency = AudioSegment(
  id: 'alert-1',
  title: 'Flash Flood Warning',
  type: AudioSegmentType.emergencyAlert,
  priority: PlaybackPriority.emergencyAlert,
  interruptible: false,
  resumeAfter: true,
);

void main() {
  group('QueueManagerService', () {
    test('insertPriority orders by priority; insertNext forces front', () {
      final q = QueueManagerService();
      const music = AudioSegment(
        id: 'm',
        title: 'M',
        type: AudioSegmentType.music,
        priority: PlaybackPriority.music,
      );
      const safety = AudioSegment(
        id: 's',
        title: 'S',
        type: AudioSegmentType.safetyWarning,
        priority: PlaybackPriority.safetyWarning,
      );
      const announcement = AudioSegment(
        id: 'a',
        title: 'A',
        type: AudioSegmentType.announcement,
        priority: PlaybackPriority.scheduledAnnouncement,
      );

      q.enqueue(music);
      q.insertPriority(safety);
      q.insertPriority(announcement);

      expect(
        q.items.map((i) => i.priority).toList(),
        [
          PlaybackPriority.safetyWarning,
          PlaybackPriority.scheduledAnnouncement,
          PlaybackPriority.music,
        ],
      );

      final forced = q.insertNext(_emergency);
      expect(q.peekNext(), forced);
    });

    test('pauseMusic / resumeMusic round-trips the same item', () {
      final q = QueueManagerService();
      const music = AudioSegment(
        id: 'm',
        title: 'M',
        type: AudioSegmentType.music,
        priority: PlaybackPriority.music,
      );
      final item = q.enqueue(music);
      q.skip(); // "play" it

      q.pauseMusic(item);
      expect(q.pausedMusic, item);

      final resumed = q.resumeMusic();
      expect(resumed, item);
      expect(q.pausedMusic, isNull);
      expect(q.peekNext(), item);
    });
  });

  group('RadioEngineService', () {
    test('emergency interrupts music and music resumes afterwards', () {
      final engine = buildEngine();
      engine.station.load(
        station: const RadioStation(id: 's1', name: 'Trail Radio'),
        playlist: const [
          Song(id: '1', stationId: 's1', title: 'Song One'),
          Song(id: '2', stationId: 's1', title: 'Song Two'),
        ],
      );

      engine.start();
      expect(engine.playback.current!.segment.type, AudioSegmentType.music);
      final firstMusicId = engine.playback.current!.segment.id;

      engine.requestInterruption(_emergency);
      expect(engine.playback.current!.segment.type,
          AudioSegmentType.emergencyAlert);
      expect(engine.queue.pausedMusic, isNotNull);

      engine.onSegmentCompleted(); // emergency ends -> resume music
      expect(engine.playback.current!.segment.id, firstMusicId);
      expect(engine.queue.pausedMusic, isNull);
    });

    test('a story narration is woven in after music, then music continues', () {
      final engine = buildEngine();
      engine.station.load(
        station: const RadioStation(id: 's1', name: 'Trail Radio'),
        playlist: const [
          Song(id: '1', stationId: 's1', title: 'Song One'),
          Song(id: '2', stationId: 's1', title: 'Song Two'),
        ],
      );
      engine.stories.configure(
        everyTracks: 1,
        narrations: [
          AudioSegment.fromNarration(
            const Narration(id: 'n1', storyId: 'st1', title: 'Ranger Tale'),
          ),
        ],
      );

      engine.start(); // plays Song One
      expect(engine.playback.current!.segment.type, AudioSegmentType.music);

      engine.onSegmentCompleted(); // after music -> narration due
      expect(engine.playback.current!.segment.type,
          AudioSegmentType.narration);

      engine.onSegmentCompleted(); // narration ends -> next music
      expect(engine.playback.current!.segment.type, AudioSegmentType.music);
    });

    test('GPS scheduler is present but does not decide anything yet', () {
      final engine = buildEngine();
      expect(engine.gps.evaluate(null), isNull);
    });
  });
}
