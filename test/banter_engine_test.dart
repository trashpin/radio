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
  String? community,
  double? triggerRadius,
  List<String> audio = const [],
  String? script,
  String? description,
  ContentStatus? contentStatus,
}) =>
    MasterLocation(
      id: id,
      name: id,
      type: type,
      latitude: _baseLat + _lat(miles),
      longitude: _baseLng,
      county: county,
      city: city,
      community: community,
      triggerRadius: triggerRadius,
      audioFiles: audio,
      narrationScript: script,
      description: description,
      contentStatus: contentStatus,
    );

const _engine = BanterEngine();

// A Marion County world: a state park (with a tagged in-park spring), a city
// (with a city-tagged diner), a county museum, plus rows that must be excluded.
final _park = _loc('State Park', LocationType.statePark,
    miles: 0, triggerRadius: 16000, audio: ['https://x/park.mp3']);
final _parkSpring = _loc('Park Spring', LocationType.spring,
    miles: 0.2, community: 'State Park', description: 'A spring in the park.');
final _city = _loc('Ocala', LocationType.city,
    miles: 0.5, triggerRadius: 8000, description: 'The city of Ocala.');
final _cityDiner = _loc('Ocala Diner', LocationType.restaurant,
    miles: 0.6, city: 'Ocala', description: 'A diner in Ocala.');
final _countyMuseum = _loc('County Museum', LocationType.museum,
    miles: 3, description: 'A Marion County museum.');
final _otherCounty = _loc('Duval Thing', LocationType.attraction,
    miles: 2, county: 'Duval', description: 'Elsewhere.');
final _draft = _loc('Draft POI', LocationType.museum,
    miles: 0.1, description: 'Hidden draft.', contentStatus: ContentStatus.draft);
final _empty = _loc('Empty', LocationType.museum, miles: 0.1); // no content

final _world = [
  _park, _parkSpring, _city, _cityDiner, _countyMuseum,
  _otherCounty, _draft, _empty,
];

void main() {
  final now = DateTime(2026, 8, 5, 12);

  group('pool building (data-driven scope)', () {
    test('scopes by identity + city/community fields; excludes ineligible', () {
      final pool = _engine.buildPool(_baseLat, _baseLng, _world, county: 'Marion');
      final byId = {for (final c in pool) c.location.id: c.scope};
      expect(byId['State Park'], BanterScope.park);
      expect(byId['Park Spring'], BanterScope.park); // community == park name
      expect(byId['Ocala'], BanterScope.city);
      expect(byId['Ocala Diner'], BanterScope.city); // city field match
      expect(byId['County Museum'], BanterScope.county);
      // Excluded entirely:
      expect(byId.containsKey('Duval Thing'), isFalse); // other county
      expect(byId.containsKey('Draft POI'), isFalse); // publish-blocked
      expect(byId.containsKey('Empty'), isFalse); // no content
    });
  });

  group('priority park > city > county', () {
    test('inside a park, park banter is chosen first', () {
      final pick = _engine.selectNext(_baseLat, _baseLng, _world, now: now, county: 'Marion');
      expect(pick, isNotNull);
      expect(pick!.scope, BanterScope.park);
    });

    test('when park clips are cooling down, falls back to city', () {
      final pick = _engine.selectNext(_baseLat, _baseLng, _world, now: now, county: 'Marion',
          lastPlayed: {'State Park': now, 'Park Spring': now});
      expect(pick!.scope, BanterScope.city);
    });

    test('when park + city cooling down, falls back to county (Marion)', () {
      final pick = _engine.selectNext(_baseLat, _baseLng, _world, now: now, county: 'Marion',
          lastPlayed: {
            'State Park': now,
            'Park Spring': now,
            'Ocala': now,
            'Ocala Diner': now,
          });
      expect(pick!.scope, BanterScope.county);
      expect(pick.location.id, 'County Museum');
    });
  });

  group('cooldown', () {
    test('a clip does not repeat within the cooldown window', () {
      const cfg = BanterConfig(cooldown: Duration(minutes: 20));
      const engine = BanterEngine(cfg);
      // Only one park clip available, played 5 min ago → still cooling down →
      // engine must NOT pick it again; it falls to city instead.
      final pick = engine.selectNext(_baseLat, _baseLng, _world,
          now: now,
          county: 'Marion',
          lastPlayed: {
            'State Park': now.subtract(const Duration(minutes: 5)),
            'Park Spring': now.subtract(const Duration(minutes: 5)),
          });
      expect(pick!.scope, BanterScope.city);
    });

    test('after the cooldown expires the clip is eligible again', () {
      final pick = _engine.selectNext(_baseLat, _baseLng, _world,
          now: now,
          county: 'Marion',
          lastPlayed: {
            'State Park': now.subtract(const Duration(minutes: 25)),
            'Park Spring': now.subtract(const Duration(minutes: 25)),
          });
      expect(pick!.scope, BanterScope.park);
    });
  });

  group('county fallback (Marion) when not inside a park/city', () {
    test('far from any park/city, everything is county banter', () {
      // 60 mi north — outside every park/city radius.
      final pick = _engine.selectNext(_baseLat + _lat(60), _baseLng, _world,
          now: now, county: 'Marion');
      expect(pick, isNotNull);
      expect(pick!.scope, BanterScope.county);
    });
  });

  group('LocationBanterScheduler', () {
    test('emits a playable segment reusing location audio, then cools down', () {
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
      // Park has recorded audio → played as an audio url, not TTS.
      expect(seg.audioUrl, 'https://x/park.mp3');
      expect(seg.resumeAfter, isFalse);
    });

    test('disabled scheduler never emits', () {
      final scheduler = LocationBanterScheduler(everyNSongs: 1)..enabled = false;
      scheduler.configure(context: () => BanterRuntime(
            lat: _baseLat, lng: _baseLng, county: 'Marion', locations: _world,
            resolve: (l) => const BanterClip(text: 'x')));
      expect(scheduler.onMusicPlayed(), isNull);
    });
  });
}
