// Unit tests for the AI Producer. It's a pure decision function, so we feed it
// crafted ProducerContexts and assert which decision (and reason) it returns.

import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
import 'package:explorer_os_mobile/features/radio/producer/decision_reason.dart';
import 'package:explorer_os_mobile/features/radio/producer/producer_context.dart';
import 'package:explorer_os_mobile/features/radio/producer/producer_engine.dart';
import 'package:flutter_test/flutter_test.dart';

const _music = AudioSegment(
  id: 'music',
  title: 'Trail Song',
  type: AudioSegmentType.music,
  priority: PlaybackPriority.music,
);
const _emergency = AudioSegment(
  id: 'emg',
  title: 'Flash Flood',
  type: AudioSegmentType.emergencyAlert,
  priority: PlaybackPriority.emergencyAlert,
  interruptible: false,
  resumeAfter: true,
);
const _safety = AudioSegment(
  id: 'safe',
  title: 'Trail Closed',
  type: AudioSegmentType.safetyWarning,
  priority: PlaybackPriority.safetyWarning,
  interruptible: false,
  resumeAfter: true,
);
const _navigation = AudioSegment(
  id: 'nav',
  title: 'Turn left',
  type: AudioSegmentType.gpsNarration,
  priority: PlaybackPriority.gpsNarration,
  interruptible: false,
  resumeAfter: true,
);
const _story = AudioSegment(
  id: 'story',
  title: 'Ranger Tale',
  type: AudioSegmentType.narration,
  priority: PlaybackPriority.scheduledAnnouncement,
  interruptible: false,
  resumeAfter: true,
);
const _stationId = AudioSegment(
  id: 'sid',
  title: 'You are listening to Explorer Radio',
  type: AudioSegmentType.stationIdentification,
  priority: PlaybackPriority.stationIdentification,
  resumeAfter: true,
);
const _ambient = AudioSegment(
  id: 'amb',
  title: 'Forest sounds',
  type: AudioSegmentType.ambient,
  priority: PlaybackPriority.ambientAudio,
);

ProducerContext ctx({
  AudioSegment? emergency,
  AudioSegment? safety,
  AudioSegment? navigation,
  AudioSegment? story,
  AudioSegment? attraction,
  AudioSegment? stationId,
  AudioSegment? music,
  AudioSegment? ambient,
  AudioSegment? current,
  bool hasPausedMusic = false,
  int tracksSinceStory = 0,
  int tracksSinceStationId = 0,
  String? parkId,
}) {
  return ProducerContext(
    now: DateTime(2026, 7, 24, 14),
    pendingEmergency: emergency,
    pendingSafety: safety,
    pendingNavigation: navigation,
    scheduledStory: story,
    upcomingAttraction: attraction,
    stationId: stationId,
    nextMusic: music,
    ambient: ambient,
    currentSegment: current,
    hasPausedMusic: hasPausedMusic,
    tracksSinceStory: tracksSinceStory,
    tracksSinceStationId: tracksSinceStationId,
    parkId: parkId,
  );
}

void main() {
  final producer = ProducerEngine();

  group('determineNextItem priority ladder', () {
    test('emergency overrides everything', () {
      final d = producer.determineNextItem(
        ctx(emergency: _emergency, music: _music, story: _story, tracksSinceStory: 9),
      );
      expect(d.reason, DecisionReason.emergency);
      expect(d.interrupt, isTrue);
      expect(d.item!.segment.id, 'emg');
    });

    test('safety beats navigation and music', () {
      final d = producer
          .determineNextItem(ctx(safety: _safety, navigation: _navigation, music: _music));
      expect(d.reason, DecisionReason.safety);
    });

    test('story plays only when its cadence has elapsed', () {
      expect(
        producer.determineNextItem(ctx(story: _story, music: _music, tracksSinceStory: 3)).reason,
        DecisionReason.scheduledStory,
      );
      expect(
        producer.determineNextItem(ctx(story: _story, music: _music, tracksSinceStory: 1)).reason,
        DecisionReason.music,
      );
    });

    test('station ID plays when due', () {
      final d = producer.determineNextItem(
        ctx(stationId: _stationId, music: _music, tracksSinceStationId: 5),
      );
      expect(d.reason, DecisionReason.stationIdentification);
    });

    test('music is the baseline; location context yields locationMusic', () {
      expect(producer.determineNextItem(ctx(music: _music)).reason,
          DecisionReason.music);
      expect(
        producer.determineNextItem(ctx(music: _music, parkId: 'p1')).reason,
        DecisionReason.locationMusic,
      );
    });

    test('ambient fills when only ambient is available', () {
      expect(producer.determineNextItem(ctx(ambient: _ambient)).reason,
          DecisionReason.ambient);
    });

    test('nothing to play when no candidates', () {
      final d = producer.determineNextItem(ctx());
      expect(d.reason, DecisionReason.nothingToPlay);
      expect(d.hasItem, isFalse);
    });
  });

  group('should* helpers', () {
    test('shouldInterrupt respects interruptible except for critical alerts', () {
      // Interruptible music + safety -> interrupt.
      expect(producer.shouldInterrupt(ctx(current: _music, safety: _safety)), isTrue);
      // Non-interruptible narration + navigation (non-critical) -> no interrupt.
      expect(producer.shouldInterrupt(ctx(current: _story, navigation: _navigation)),
          isFalse);
      // Non-interruptible narration + emergency (critical) -> interrupt anyway.
      expect(producer.shouldInterrupt(ctx(current: _story, emergency: _emergency)),
          isTrue);
    });

    test('shouldResumeMusic only when paused music and nothing higher pending', () {
      expect(producer.shouldResumeMusic(ctx(hasPausedMusic: true)), isTrue);
      expect(
        producer.shouldResumeMusic(ctx(hasPausedMusic: true, emergency: _emergency)),
        isFalse,
      );
      expect(producer.shouldResumeMusic(ctx(hasPausedMusic: false)), isFalse);
    });

    test('shouldPlayLocationMusic needs music + location context', () {
      expect(producer.shouldPlayLocationMusic(ctx(music: _music, parkId: 'p1')), isTrue);
      expect(producer.shouldPlayLocationMusic(ctx(music: _music)), isFalse);
    });
  });
}
