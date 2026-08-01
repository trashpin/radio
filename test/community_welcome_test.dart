import 'package:explorer_os_mobile/features/radio/discovery/community_welcome_director.dart';
import 'package:flutter_test/flutter_test.dart';

// A community centered at (29.0, -82.0). Points placed due north by D meters:
// 1° latitude ≈ 111320 m.
const _lat0 = 29.0;
const _lng0 = -82.0;
(double, double) posNorth(double meters) => (_lat0 + meters / 111320.0, _lng0);

void main() {
  const belleview = CommunityPlace(
    id: 'belleview',
    name: 'Belleview',
    latitude: _lat0,
    longitude: _lng0,
  ); // entry 800m, approach 1609m by default

  test('approach fires once ~1 mile out, then entry once inside, no repeats',
      () {
    final d = CommunityWelcomeDirector();

    // Far outside the approach ring but not yet "reset-far" — nothing to say.
    var (lat, lng) = posNorth(3000);
    expect(d.evaluate(lat, lng, [belleview]), isNull);

    // Enter the 1-mile approach ring (outside the 0.5-mile entry ring).
    (lat, lng) = posNorth(1200);
    final approach = d.evaluate(lat, lng, [belleview]);
    expect(approach, isNotNull);
    expect(approach!.kind, CommunityCueKind.approach);
    expect(approach.place.name, 'Belleview');

    // Still approaching → must NOT repeat the heads-up.
    (lat, lng) = posNorth(1000);
    expect(d.evaluate(lat, lng, [belleview]), isNull);

    // Cross into the community → entry welcome fires once.
    (lat, lng) = posNorth(400);
    final entry = d.evaluate(lat, lng, [belleview]);
    expect(entry, isNotNull);
    expect(entry!.kind, CommunityCueKind.entry);

    // Still inside → no repeat.
    (lat, lng) = posNorth(300);
    expect(d.evaluate(lat, lng, [belleview]), isNull);
  });

  test('a new visit (drive well clear then return) re-triggers', () {
    final d = CommunityWelcomeDirector();

    var (lat, lng) = posNorth(1200);
    expect(d.evaluate(lat, lng, [belleview])!.kind, CommunityCueKind.approach);

    // Drive well clear (> approach + leave margin ≈ 4.8 km) → visit resets.
    (lat, lng) = posNorth(6000);
    expect(d.evaluate(lat, lng, [belleview]), isNull);

    // Return → the approach heads-up plays again for the new visit.
    (lat, lng) = posNorth(1200);
    final again = d.evaluate(lat, lng, [belleview]);
    expect(again, isNotNull);
    expect(again!.kind, CommunityCueKind.approach);
  });

  test('arriving directly inside (no approach) still welcomes once', () {
    final d = CommunityWelcomeDirector();
    final (lat, lng) = posNorth(200); // already inside the entry ring
    final cue = d.evaluate(lat, lng, [belleview]);
    expect(cue!.kind, CommunityCueKind.entry);
    // No further cues while parked inside.
    expect(d.evaluate(lat, lng, [belleview]), isNull);
  });

  test('nearest community is chosen when two are in range', () {
    final d = CommunityWelcomeDirector();
    const near = CommunityPlace(
        id: 'near', name: 'Near', latitude: _lat0, longitude: _lng0);
    // ~1.2km east of center → still within approach, but farther than `near`.
    final far = CommunityPlace(
        id: 'far', name: 'Far', latitude: _lat0, longitude: _lng0 + 0.012);
    final (lat, lng) = posNorth(1000);
    final cue = d.evaluate(lat, lng, [far, near]);
    expect(cue!.place.id, 'near');
  });
}
