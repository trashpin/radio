import 'dart:async';

import 'package:explorer_os_mobile/features/gps/models/travel_context.dart';
import 'package:explorer_os_mobile/features/gps/models/upcoming_destination.dart';
import 'package:explorer_os_mobile/features/gps/services/gps_service.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/geo_point.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
import 'package:explorer_os_mobile/features/radio/producer/playback_decision.dart';
import 'package:explorer_os_mobile/features/radio/producer/producer_context.dart';
import 'package:explorer_os_mobile/features/radio/producer/producer_engine.dart';
import 'package:explorer_os_mobile/features/radio/services/radio_engine_service.dart';

/// The integration layer that turns three independent engines into ONE system.
///
/// WHY THIS EXISTS: the GPS Intelligence Engine, the AI Producer, and the
/// Explorer Radio engine are each self-contained and decoupled. Something has to
/// connect them — this coordinator is that seam (and the only place allowed to
/// depend on all three). It:
///   1. subscribes to the GPS engine's `TravelContext` stream,
///   2. maps each context into the Producer's `ProducerContext` (converting
///      GPS coordinates → the radio `GeoPoint`, surfacing the upcoming
///      attraction, and reading the Radio engine's current playback state),
///   3. asks the `ProducerEngine` what should play, and
///   4. forwards interrupting decisions (e.g. an approaching location story) to
///      the `RadioEngineService` via `requestInterruption`.
///
/// The Radio engine keeps running the continuous station flow (music/story/
/// announcement cadence); this coordinator only injects GPS-driven interruptions
/// so the audio reacts to the journey. It is deterministic and side-effect
/// contained — `onTravelContext` can be called directly in tests.
class TravelCompanionService {
  TravelCompanionService({
    required this.producer,
    required this.radioEngine,
  });

  final ProducerEngine producer;
  final RadioEngineService radioEngine;

  StreamSubscription<TravelContext>? _subscription;
  String? _lastInterruptSegmentId;

  final StreamController<PlaybackDecision> _decisions =
      StreamController<PlaybackDecision>.broadcast();

  /// Observable stream of the decisions this coordinator makes (for logging/UI).
  Stream<PlaybackDecision> get decisions => _decisions.stream;

  /// Begins reacting to the GPS engine's travel context.
  void attachTo(GPSService gps) {
    _subscription = gps.travelContextStream.listen(onTravelContext);
  }

  Future<void> detach() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Maps a GPS [TravelContext] into the Producer's [ProducerContext], pulling
  /// current playback state from the Radio engine. Pure — no side effects.
  ProducerContext buildProducerContext(TravelContext tc) {
    final radioState = radioEngine.state;
    final location = tc.location;

    return ProducerContext(
      now: tc.timestamp,
      gpsLocation: location == null
          ? null
          : GeoPoint(
              latitude: location.latitude, longitude: location.longitude),
      parkId: tc.currentParkId,
      stateName: tc.currentStateName,
      destinationId: tc.currentDestinationId,
      queueLength: radioState.queue.length,
      currentSegment: radioState.current?.segment,
      hasPausedMusic: radioState.interruptedItem != null,
      upcomingAttraction: tc.nextAttraction == null
          ? null
          : _attractionSegment(tc.nextAttraction!),
    );
  }

  /// Handles one travel-context update: decide, publish, and forward any
  /// interruption to the Radio engine (idempotent per attraction).
  PlaybackDecision onTravelContext(TravelContext tc) {
    final decision = producer.determineNextItem(buildProducerContext(tc));
    _decisions.add(decision);

    final item = decision.item;
    if (decision.interrupt && item != null) {
      if (item.segment.id != _lastInterruptSegmentId) {
        radioEngine.requestInterruption(item.segment);
        _lastInterruptSegmentId = item.segment.id;
      }
    }
    return decision;
  }

  /// Builds a location-story [AudioSegment] for an upcoming attraction. Until
  /// backend audio is wired, `audioUrl` is null (the decision/timing is what
  /// matters); a later step resolves the real narration/GPS-trigger audio.
  AudioSegment _attractionSegment(UpcomingDestination attraction) {
    return AudioSegment(
      id: 'attraction:${attraction.id}',
      title: attraction.name,
      type: AudioSegmentType.gpsNarration,
      priority: PlaybackPriority.gpsNarration,
      interruptible: false,
      resumeAfter: true,
      parkId: attraction.parkId,
      location: GeoPoint(
        latitude: attraction.latitude,
        longitude: attraction.longitude,
      ),
    );
  }

  void dispose() {
    _subscription?.cancel();
    _decisions.close();
  }
}
