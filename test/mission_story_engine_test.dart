import 'package:explorer_os_mobile/features/missions/models/mission_stop.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_travel_story.dart';
import 'package:explorer_os_mobile/features/missions/services/mission_story_engine.dart';
import 'package:flutter_test/flutter_test.dart';

// Ocala, FL area. 1 degree of latitude ~= 111,320 meters — used to place the
// player at precise distances from the stop for deterministic assertions.
const _stopLat = 29.1872;
const _stopLng = -82.1401;

MissionStop _stop({double arrivalRadiusMeters = 150}) => MissionStop(
      id: 'stop-1',
      missionId: 'mission-1',
      sequence: 1,
      title: 'Test Stop',
      latitude: _stopLat,
      longitude: _stopLng,
      arrivalRadiusMeters: arrivalRadiusMeters,
    );

MissionTravelStory _story(
  String id, {
  required double triggerDistanceMeters,
  String triggerType = 'travel',
  int priority = 0,
}) =>
    MissionTravelStory(
      id: id,
      missionId: 'mission-1',
      stopId: 'stop-1',
      triggerType: triggerType,
      triggerDistanceMeters: triggerDistanceMeters,
      text: 'Story $id',
      priority: priority,
    );

/// A lat/lng approximately [meters] north of the stop.
(double, double) _pointAtDistance(double meters) {
  const metersPerDegree = 111320.0;
  return (_stopLat + meters / metersPerDegree, _stopLng);
}

void main() {
  const engine = MissionStoryEngine();

  group('travel story triggers', () {
    test('fires the nearest crossed trigger the player hasn\'t heard yet', () {
      final stop = _stop();
      final stories = [
        _story('5mi', triggerDistanceMeters: 8047), // ~5 miles
        _story('3mi', triggerDistanceMeters: 4828), // ~3 miles
        _story('1mi', triggerDistanceMeters: 1609), // ~1 mile
      ];
      final (lat, lng) = _pointAtDistance(4000); // between 3mi and 1mi triggers
      final result = engine.evaluate(
        lat: lat, lng: lng, targetStop: stop, stories: stories, alreadyFiredIds: {});
      expect(result.action, MissionEngineAction.playTravelStory);
      expect(result.story!.id, '3mi');
    });

    test('never re-fires a story already in alreadyFiredIds', () {
      final stop = _stop();
      final stories = [_story('3mi', triggerDistanceMeters: 4828)];
      final (lat, lng) = _pointAtDistance(4000);
      final result = engine.evaluate(
        lat: lat, lng: lng, targetStop: stop, stories: stories,
        alreadyFiredIds: {'3mi'});
      expect(result.action, MissionEngineAction.none);
    });

    test('does not fire a trigger the player has not reached yet', () {
      final stop = _stop();
      final stories = [_story('1mi', triggerDistanceMeters: 1609)];
      final (lat, lng) = _pointAtDistance(5000); // still far from the 1mi trigger
      final result = engine.evaluate(
        lat: lat, lng: lng, targetStop: stop, stories: stories, alreadyFiredIds: {});
      expect(result.action, MissionEngineAction.none);
    });

    test('priority breaks ties between two simultaneously-crossed triggers', () {
      final stop = _stop();
      final stories = [
        _story('low', triggerDistanceMeters: 2000, priority: 0),
        _story('high', triggerDistanceMeters: 2000, priority: 10),
      ];
      final (lat, lng) = _pointAtDistance(1500);
      final result = engine.evaluate(
        lat: lat, lng: lng, targetStop: stop, stories: stories, alreadyFiredIds: {});
      expect(result.story!.id, 'high');
    });

    test('never interrupts a narration already playing', () {
      final stop = _stop();
      final stories = [_story('3mi', triggerDistanceMeters: 4828)];
      final (lat, lng) = _pointAtDistance(4000);
      final result = engine.evaluate(
        lat: lat, lng: lng, targetStop: stop, stories: stories,
        alreadyFiredIds: {}, isNarrationPlaying: true);
      expect(result.action, MissionEngineAction.none);
    });
  });

  group('arrival', () {
    test('fires arrival once inside the arrival radius, taking priority over travel stories', () {
      final stop = _stop(arrivalRadiusMeters: 150);
      final stories = [_story('close', triggerDistanceMeters: 500)];
      final (lat, lng) = _pointAtDistance(100); // inside both the story trigger and arrival radius
      final result = engine.evaluate(
        lat: lat, lng: lng, targetStop: stop, stories: stories, alreadyFiredIds: {});
      expect(result.action, MissionEngineAction.arrive);
      expect(result.stop!.id, stop.id);
    });

    test('never re-fires arrival once already recorded', () {
      final stop = _stop(arrivalRadiusMeters: 150);
      final (lat, lng) = _pointAtDistance(50);
      final result = engine.evaluate(
        lat: lat, lng: lng, targetStop: stop, stories: const [],
        alreadyFiredIds: {missionArrivalFiredKey(stop.id)});
      expect(result.action, MissionEngineAction.none);
    });
  });

  test('distanceMeters is always reported, even when no action fires', () {
    final stop = _stop();
    final (lat, lng) = _pointAtDistance(9000);
    final result = engine.evaluate(
      lat: lat, lng: lng, targetStop: stop, stories: const [], alreadyFiredIds: {});
    expect(result.action, MissionEngineAction.none);
    expect(result.distanceMeters, greaterThan(8000));
  });
}
