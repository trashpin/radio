// Tests for the expanded Radio Engine: new segment models/factories, audio
// categories, the priority additions, and the engine's public control surface
// (queue ops, volume/mute, change station, events, previous).

import 'package:explorer_os_mobile/features/radio/events/radio_event.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
import 'package:explorer_os_mobile/features/radio/models/safety_alert.dart';
import 'package:explorer_os_mobile/features/radio/models/station_id.dart';
import 'package:explorer_os_mobile/features/radio/models/weather_update.dart';
import 'package:explorer_os_mobile/features/radio/services/announcement_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/gps_audio_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/history_manager.dart';
import 'package:explorer_os_mobile/features/radio/services/playback_controller.dart';
import 'package:explorer_os_mobile/features/radio/services/queue_manager_service.dart';
import 'package:explorer_os_mobile/features/radio/services/radio_engine_service.dart';
import 'package:explorer_os_mobile/features/radio/services/station_manager.dart';
import 'package:explorer_os_mobile/features/radio/services/story_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/user_preference_manager.dart';
import 'package:explorer_os_mobile/shared/models/radio_station.dart';
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

const _music = AudioSegment(
  id: 'm1',
  title: 'Trail Song',
  type: AudioSegmentType.music,
  priority: PlaybackPriority.music,
);

void main() {
  group('models & enums', () {
    test('content models map to correctly-typed segments', () {
      expect(const WeatherUpdate(id: 'w', title: 'Weather').toSegment().type,
          AudioSegmentType.weather);
      final emergency = const SafetyAlert(
        id: 's',
        title: 'Flood',
        severity: SafetyAlertSeverity.emergency,
      ).toSegment();
      expect(emergency.priority, PlaybackPriority.emergencyAlert);
      expect(emergency.type, AudioSegmentType.emergencyBroadcast);
      expect(
        const StationID(id: 'i', stationId: 'x', title: 'ID').toSegment().type,
        AudioSegmentType.stationIdentification,
      );
    });

    test('audio categories group segment types', () {
      expect(AudioSegmentType.music.category, AudioCategory.music);
      expect(AudioSegmentType.commercial.category, AudioCategory.commercial);
      expect(AudioSegmentType.safetyWarning.category, AudioCategory.alert);
      expect(AudioSegmentType.narration.category, AudioCategory.spokenWord);
    });

    test('priority adds lowPriority and AudioPriority aliases', () {
      expect(PlaybackPriority.lowPriority.rank, 7);
      const AudioPriority p = PlaybackPriority.music; // alias compiles
      expect(p, PlaybackPriority.music);
    });
  });

  group('engine control surface', () {
    test('enqueue / getCurrentQueue / clearQueue', () {
      final engine = buildEngine();
      engine.enqueue(_music);
      expect(engine.getCurrentQueue().length, 1);
      engine.clearQueue();
      expect(engine.getCurrentQueue().isEmpty, isTrue);
    });

    test('volume and mute route through the audio-focus manager', () {
      final engine = buildEngine();
      engine.setVolume(0.5);
      expect(engine.audioFocus.volume, 0.5);
      engine.mute();
      expect(engine.audioFocus.isMuted, isTrue);
      engine.unmute();
      expect(engine.audioFocus.isMuted, isFalse);
    });

    test('play emits SegmentStarted for the queued item', () async {
      final engine = buildEngine();
      final events = <RadioEvent>[];
      final sub = engine.events.listen(events.add);

      engine.enqueue(_music);
      engine.play();
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<SegmentStarted>().single.segment.id, 'm1');
      await sub.cancel();
    });

    test('changeStation loads the station and emits StationChanged', () async {
      final engine = buildEngine();
      final events = <RadioEvent>[];
      final sub = engine.events.listen(events.add);

      engine.changeStation(const RadioStation(id: 's2', name: 'Country Roads'));
      await Future<void>.delayed(Duration.zero);

      expect(engine.getCurrentStation()?.id, 's2');
      expect(events.whereType<StationChanged>().single.stationId, 's2');
      await sub.cancel();
    });

    test('previous replays the last played segment', () {
      final engine = buildEngine();
      engine.enqueue(_music);
      engine.play(); // plays m1
      engine.onSegmentCompleted(); // records m1 in history, advances
      engine.previous(); // should replay m1
      expect(engine.getPlaybackState().current?.segment.id, 'm1');
    });
  });
}
