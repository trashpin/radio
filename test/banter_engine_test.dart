import 'package:explorer_os_mobile/features/locations/active_location_types.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/radio/banter/banter_engine.dart';
import 'package:explorer_os_mobile/features/radio/banter/location_banter_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:flutter_test/flutter_test.dart';

double _lat(double miles) => miles * 1609.344 / 111320.0;

const _baseLat = 29.19;
const _baseLng = -82.14;

MasterLocation _loc(
  String id,
  LocationType type, {
  double miles = 0,
  String county = 'Marion',
  String? city,
  double? triggerRadius,
  List<String> audio = const [],
  String? description = 'desc',
}) =>
    MasterLocation(
      id: id,
      name: id,
      type: type,
      latitude: _baseLat + _lat(miles),
      longitude: _baseLng,
      county: county,
      city: city,
      triggerRadius: triggerRadius,
      audioFiles: audio,
      description: description,
    );

const _engine = BanterEngine();

// A Marion County world spanning all six active tiers, plus rows that must be
// excluded (a restaurant = inactive type; a spring in another county).
final _county = _loc('Marion County', LocationType.county, miles: 0,
    audio: ['https://x/county.mp3']);
final _city = _loc('Ocala', LocationType.city, miles: 0.5, triggerRadius: 8000);
final _otherCity = _loc('Belleview', LocationType.city, miles: 8); // not current
final _park = _loc('Tuscawilla Park', LocationType.cityPark,
    miles: 0.6, city: 'Ocala');
final _statePark =
    _loc('Silver Springs State Park', LocationType.statePark, miles: 2);
final _spring = _loc('Fern Hammock Springs', LocationType.spring, miles: 3);
final _museum = _loc('Appleton Museum', LocationType.museum, miles: 0.3);
final _restaurant = _loc('Cafe', LocationType.restaurant, miles: 0.1);
final _otherCountySpring =
    _loc('Duval Spring', LocationType.spring, miles: 2, county: 'Duval');

final _world = [
  _county, _city, _otherCity, _park, _statePark, _spring,
  _museum, _restaurant, _otherCountySpring,
];

void main() {
  final now = DateTime(2026, 8, 5, 12);

  test('active-type allow-list is exactly the six tiers', () {
    expect(isActiveLocationType(LocationType.county), isTrue);
    expect(isActiveLocationType(LocationType.city), isTrue);
    expect(isActiveLocationType(LocationType.cityPark), isTrue);
    expect(isActiveLocationType(LocationType.statePark), isTrue);
    expect(isActiveLocationType(LocationType.spring), isTrue);
    expect(isActiveLocationType(LocationType.museum), isTrue);
    for (final t in [
      LocationType.restaurant,
      LocationType.coffeeShop,
      LocationType.lake,
      LocationType.historicSite,
      LocationType.trail,
      LocationType.hiddenGem,
      LocationType.gasStation,
    ]) {
      expect(isActiveLocationType(t), isFalse, reason: '$t must be excluded');
    }
  });

  test('pool includes county + current city + nearby park/statePark/spring/'
      'museum; excludes inactive types, other counties, and non-current '
      'cities', () {
    final pool = _engine.buildPool(_baseLat, _baseLng, _world, county: 'Marion');
    final byId = {for (final c in pool) c.location.id: c.tier};
    expect(byId['Marion County'], LocationTier.county);
    expect(byId['Ocala'], LocationTier.city);
    expect(byId['Tuscawilla Park'], LocationTier.park);
    expect(byId['Silver Springs State Park'], LocationTier.statePark);
    expect(byId['Fern Hammock Springs'], LocationTier.spring);
    expect(byId['Appleton Museum'], LocationTier.museum);
    // Excluded:
    expect(byId.containsKey('Cafe'), isFalse); // inactive type
    expect(byId.containsKey('Duval Spring'), isFalse); // other county
    expect(byId.containsKey('Belleview'), isFalse); // not the current city
  });

  group('narration priority County ▸ City ▸ Park ▸ State Park ▸ Spring ▸ '
      'Museum', () {
    BanterCandidate? pick(Map<String, DateTime> cooling) => _engine.selectNext(
        _baseLat, _baseLng, _world,
        now: now, county: 'Marion', lastPlayed: cooling);

    test('county wins first', () {
      expect(pick({})!.tier, LocationTier.county);
    });
    test('then city', () {
      expect(pick({'Marion County': now})!.tier, LocationTier.city);
    });
    test('then park', () {
      expect(pick({'Marion County': now, 'Ocala': now})!.tier,
          LocationTier.park);
    });
    test('then state park', () {
      expect(
          pick({'Marion County': now, 'Ocala': now, 'Tuscawilla Park': now})!
              .tier,
          LocationTier.statePark);
    });
    test('then spring', () {
      final cool = {
        'Marion County': now,
        'Ocala': now,
        'Tuscawilla Park': now,
        'Silver Springs State Park': now,
      };
      expect(pick(cool)!.tier, LocationTier.spring);
    });
    test('then museum, and null when all cool down', () {
      final cool = {
        'Marion County': now,
        'Ocala': now,
        'Tuscawilla Park': now,
        'Silver Springs State Park': now,
        'Fern Hammock Springs': now,
      };
      expect(pick(cool)!.tier, LocationTier.museum);
      expect(pick({...cool, 'Appleton Museum': now}), isNull);
    });
  });

  test('cooldown expiry re-enables a clip', () {
    final pick = _engine.selectNext(_baseLat, _baseLng, _world,
        now: now,
        county: 'Marion',
        lastPlayed: {'Marion County': now.subtract(const Duration(minutes: 25))});
    expect(pick!.tier, LocationTier.county); // 25 min > 20 min cooldown
  });

  group('LocationBanterScheduler', () {
    test('emits a playable segment reusing location audio', () {
      final scheduler = LocationBanterScheduler(everyNSongs: 1);
      scheduler.configure(context: () => BanterRuntime(
            lat: _baseLat,
            lng: _baseLng,
            county: 'Marion',
            locations: _world,
            resolve: (l) => l.audioFiles.isNotEmpty
                ? BanterClip(audioUrl: l.audioFiles.first)
                : BanterClip(text: l.description ?? l.name),
          ));
      final seg = scheduler.onMusicPlayed();
      expect(seg, isNotNull);
      expect(seg!.type, AudioSegmentType.narration);
      expect(seg.audioUrl, 'https://x/county.mp3'); // county wins, has audio
      expect(seg.resumeAfter, isFalse);
    });
  });
}
