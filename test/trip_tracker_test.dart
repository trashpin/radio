// Unit tests for the background turn-by-turn route tracker — synthetic GPS
// fixes against a fake Google Directions response (no real network calls;
// DirectionsClient's injectable getFn returns canned JSON).

import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/navigation/models/route_plan.dart';
import 'package:explorer_os_mobile/features/navigation/models/trip_progress.dart';
import 'package:explorer_os_mobile/features/navigation/services/directions_client.dart';
import 'package:explorer_os_mobile/features/navigation/services/trip_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

// A simple two-step route: straight north ~555m, then turn right ~490m east.
const _originLat = 28.0;
const _originLng = -82.0;
const _midLat = 28.005; // end of step 1 / start of step 2
const _midLng = -82.0;
const _destLat = 28.005; // end of step 2 — the destination
const _destLng = -81.995;

Map<String, dynamic> _fakeDirectionsJson() => {
      'status': 'OK',
      'routes': [
        {
          'legs': [
            {
              'distance': {'value': 1045},
              'steps': [
                {
                  'html_instructions': 'Head north',
                  'distance': {'value': 555},
                  'start_location': {'lat': _originLat, 'lng': _originLng},
                  'end_location': {'lat': _midLat, 'lng': _midLng},
                },
                {
                  'html_instructions': 'Turn <b>right</b> onto Test Rd',
                  'maneuver': 'turn-right',
                  'distance': {'value': 490},
                  'start_location': {'lat': _midLat, 'lng': _midLng},
                  'end_location': {'lat': _destLat, 'lng': _destLng},
                },
              ],
            },
          ],
        },
      ],
    };

TripTracker _buildTracker() {
  return TripTracker(
    fetchRoute: ({
      required originLat,
      required originLng,
      required destinationLat,
      required destinationLng,
      destinationName,
    }) async =>
        parseDirectionsResponse(_fakeDirectionsJson(), destinationName: destinationName),
  );
}

GPSLocation _fix(double lat, double lng) =>
    GPSLocation(latitude: lat, longitude: lng, timestamp: DateTime(2026, 1, 1));

void main() {
  group('parseDirectionsResponse', () {
    test('parses steps, maneuvers, and strips HTML from instructions', () {
      final plan = parseDirectionsResponse(_fakeDirectionsJson());
      expect(plan, isNotNull);
      expect(plan!.steps, hasLength(2));
      expect(plan.steps[0].instruction, 'Head north');
      expect(plan.steps[0].maneuver, ManeuverKind.straight);
      expect(plan.steps[1].instruction, 'Turn right onto Test Rd');
      expect(plan.steps[1].maneuver, ManeuverKind.turnRight);
      expect(plan.totalDistanceMeters, 1045);
    });

    test('returns null for a ZERO_RESULTS-style response', () {
      expect(parseDirectionsResponse({'status': 'ZERO_RESULTS'}), isNull);
    });
  });

  group('TripTracker', () {
    test('start() fetches the route and reports onRoute progress', () async {
      final tracker = _buildTracker();
      await tracker.start(
        originLat: _originLat,
        originLng: _originLng,
        destinationLat: _destLat,
        destinationLng: _destLng,
        destinationName: 'Test Destination',
      );
      expect(tracker.progress.status, TripStatus.onRoute);
      expect(tracker.progress.destinationName, 'Test Destination');
      expect(tracker.progress.distanceRemainingMeters, 1045);
    });

    test('emits ApproachingManeuver once the next turn is close enough', () async {
      final tracker = _buildTracker();
      final events = <TripEvent>[];
      tracker.events.listen(events.add);

      await tracker.start(
        originLat: _originLat,
        originLng: _originLng,
        destinationLat: _destLat,
        destinationLng: _destLng,
      );
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<TripStarted>(), hasLength(1));

      // ~300m before the end of step 1, still exactly on the route line.
      await tracker.onLocation(_fix(28.002305, _originLng));
      await Future<void>.delayed(Duration.zero);

      final approaching = events.whereType<ApproachingManeuver>().toList();
      expect(approaching, hasLength(1));
      expect(approaching.first.step.instruction, 'Head north');
      expect(approaching.first.distanceMeters, lessThan(TripTracker.approachThresholdMeters));
    });

    test('recalculates after sustained off-route drift far from any maneuver', () async {
      final tracker = _buildTracker();
      final events = <TripEvent>[];
      tracker.events.listen(events.add);

      await tracker.start(
        originLat: _originLat,
        originLng: _originLng,
        destinationLat: _destLat,
        destinationLng: _destLng,
      );

      // Off to the side near the START of the route (far from the step-1/2
      // maneuver point) — should read as "recalculating", not "missed turn".
      const offRouteLat = 28.0005;
      const offRouteLng = -82.002;
      for (var i = 0; i < TripTracker.offRouteStreakToTrigger; i++) {
        await tracker.onLocation(_fix(offRouteLat, offRouteLng));
      }
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<Recalculating>(), hasLength(1));
      expect(events.whereType<MissedTurn>(), isEmpty);
      // The fake Directions response is returned again on recalculation, so
      // tracking resumes normally rather than getting stuck.
      expect(tracker.progress.status, TripStatus.onRoute);
    });

    test('emits TripArrived within the arrival radius of the destination', () async {
      final tracker = _buildTracker();
      final events = <TripEvent>[];
      tracker.events.listen(events.add);

      await tracker.start(
        originLat: _originLat,
        originLng: _originLng,
        destinationLat: _destLat,
        destinationLng: _destLng,
      );
      await tracker.onLocation(_fix(_destLat, _destLng));
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<TripArrived>(), hasLength(1));
      expect(tracker.progress.status, TripStatus.arrived);
    });

    test('cancel() stops tracking and emits TripEnded', () async {
      final tracker = _buildTracker();
      final events = <TripEvent>[];
      tracker.events.listen(events.add);

      await tracker.start(
        originLat: _originLat,
        originLng: _originLng,
        destinationLat: _destLat,
        destinationLng: _destLng,
      );
      tracker.cancel();
      await Future<void>.delayed(Duration.zero);

      expect(tracker.progress.status, TripStatus.idle);
      expect(events.whereType<TripEnded>(), hasLength(1));
    });

    test('start() leaves progress idle when Directions returns nothing', () async {
      final tracker = TripTracker(
        fetchRoute: ({
          required originLat,
          required originLng,
          required destinationLat,
          required destinationLng,
          destinationName,
        }) async =>
            null,
      );
      await tracker.start(
        originLat: _originLat,
        originLng: _originLng,
        destinationLat: _destLat,
        destinationLng: _destLng,
      );
      expect(tracker.progress.status, TripStatus.idle);
    });
  });
}
