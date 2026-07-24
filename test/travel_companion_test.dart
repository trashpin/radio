// Unit tests for the GPS ↔ AI Producer ↔ Radio coordinator.
//
// It maps a GPS TravelContext into a ProducerContext, asks the ProducerEngine
// what to play, and forwards interruptions to the Radio engine. All three
// engines are constructed in-memory, so the integration is fully testable
// offline.

import 'package:explorer_os_mobile/features/companion/services/travel_companion_service.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/models/travel_context.dart';
import 'package:explorer_os_mobile/features/gps/models/upcoming_destination.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/producer/decision_reason.dart';
import 'package:explorer_os_mobile/features/radio/producer/producer_engine.dart';
import 'package:explorer_os_mobile/features/radio/services/announcement_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/gps_audio_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/history_manager.dart';
import 'package:explorer_os_mobile/features/radio/services/playback_controller.dart';
import 'package:explorer_os_mobile/features/radio/services/queue_manager_service.dart';
import 'package:explorer_os_mobile/features/radio/services/radio_engine_service.dart';
import 'package:explorer_os_mobile/features/radio/services/station_manager.dart';
import 'package:explorer_os_mobile/features/radio/services/story_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/user_preference_manager.dart';
import 'package:flutter_test/flutter_test.dart';

RadioEngineService buildRadioEngine() => RadioEngineService(
      queue: QueueManagerService(),
      playback: PlaybackController(),
      station: StationManager(),
      stories: StoryScheduler(),
      announcements: AnnouncementScheduler(),
      gps: GPSAudioScheduler(),
      history: HistoryManager(),
      preferences: UserPreferenceManager(),
    );

TravelContext contextWithAttraction() => TravelContext(
      timestamp: DateTime(2026, 7, 24, 14),
      location: GPSLocation(
          latitude: 40, longitude: -111, timestamp: DateTime(2026, 7, 24, 14)),
      currentParkId: 'p1',
      currentStateName: 'Utah',
      nextAttraction: const UpcomingDestination(
        id: 'a',
        name: 'North Overlook',
        latitude: 40.02,
        longitude: -111,
        distanceMeters: 800,
        bearingDegrees: 0,
      ),
    );

void main() {
  test('maps TravelContext into a ProducerContext', () {
    final companion = TravelCompanionService(
      producer: ProducerEngine(),
      radioEngine: buildRadioEngine(),
    );

    final ctx = companion.buildProducerContext(contextWithAttraction());

    expect(ctx.gpsLocation, isNotNull);
    expect(ctx.gpsLocation!.latitude, 40);
    expect(ctx.parkId, 'p1');
    expect(ctx.stateName, 'Utah');
    expect(ctx.upcomingAttraction, isNotNull);
    expect(ctx.upcomingAttraction!.type, AudioSegmentType.gpsNarration);
  });

  test('an upcoming attraction interrupts the radio (once)', () {
    final radio = buildRadioEngine();
    final companion =
        TravelCompanionService(producer: ProducerEngine(), radioEngine: radio);

    final decision = companion.onTravelContext(contextWithAttraction());

    // Producer chose the upcoming attraction and asked to interrupt.
    expect(decision.reason, DecisionReason.upcomingAttraction);
    expect(decision.interrupt, isTrue);

    // The Radio engine received the interruption (queued as gpsNarration).
    expect(radio.state.queue, isNotEmpty);
    expect(radio.state.queue.first.segment.type,
        AudioSegmentType.gpsNarration);

    // Same attraction again → not re-interrupted (idempotent).
    companion.onTravelContext(contextWithAttraction());
    expect(radio.state.queue.length, 1);
  });

  test('no attraction → nothing to play, no interruption', () {
    final radio = buildRadioEngine();
    final companion =
        TravelCompanionService(producer: ProducerEngine(), radioEngine: radio);

    final decision = companion.onTravelContext(
      TravelContext(timestamp: DateTime(2026, 7, 24, 14)),
    );

    expect(decision.reason, DecisionReason.nothingToPlay);
    expect(radio.state.queue, isEmpty);
  });
}
