import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/admin/media_manager/models/media_asset.dart';
import 'package:explorer_os_mobile/features/admin/media_search/data/openverse_client.dart';
import 'package:explorer_os_mobile/features/admin/media_search/data/wikimedia_client.dart';
import 'package:explorer_os_mobile/features/admin/media_search/data/media_search_providers.dart';
import 'package:explorer_os_mobile/features/admin/media_search/logic/image_filters.dart';
import 'package:explorer_os_mobile/features/admin/media_search/logic/image_ranking.dart';
import 'package:explorer_os_mobile/features/admin/media_search/logic/search_query.dart';
import 'package:explorer_os_mobile/features/admin/media_search/models/image_search_result.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

ImageSearchResult _r({
  ImageSource source = ImageSource.wikimedia,
  String id = 'x',
  String title = 'Silver Springs State Park',
  int? w = 2000,
  int? h = 1300,
  String? license = 'CC BY-SA 4.0',
  String? photographer = 'Jane Doe',
  String? mime = 'image/jpeg',
  String? desc,
}) =>
    ImageSearchResult(
      source: source,
      id: id,
      title: title,
      imageUrl: 'https://img/$id.jpg',
      thumbnailUrl: 'https://img/$id-thumb.jpg',
      width: w,
      height: h,
      license: license,
      photographer: photographer,
      mimeType: mime,
      description: desc,
    );

void main() {
  group('search query', () {
    const dest = SearchDestination(
        name: 'Silver Springs State Park', county: 'Marion', state: 'Florida');

    test('primary query joins name + county + state without dupes', () {
      expect(buildPrimaryQuery(dest),
          'Silver Springs State Park Marion County Florida');
    });

    test('does not repeat state when already in the name', () {
      const d = SearchDestination(name: 'Florida Caverns', state: 'Florida');
      expect(buildPrimaryQuery(d), 'Florida Caverns');
    });

    test('retry chain is ordered specific → broad and de-duplicated', () {
      final chain = buildQueryChain(dest);
      expect(chain.first, 'Silver Springs State Park Marion County Florida');
      expect(chain.last, 'Silver Springs State Park'); // broadest = name only
      expect(chain.toSet().length, chain.length); // no duplicates
    });

    test('significant tokens drop generic place words', () {
      final t = significantTokens('Silver Springs State Park');
      expect(t.contains('silver'), isTrue);
      expect(t.contains('springs'), isTrue);
      expect(t.contains('state'), isFalse);
      expect(t.contains('park'), isFalse);
    });
  });

  group('quality gate', () {
    test('rejects images narrower than the floor', () {
      expect(passesQualityGate(_r(w: 800)), isFalse);
      expect(passesQualityGate(_r(w: 1600)), isTrue);
    });

    test('rejects logos / maps / diagrams by title', () {
      expect(passesQualityGate(_r(title: 'Official park logo')), isFalse);
      expect(passesQualityGate(_r(title: 'Map of Ocala National Forest')),
          isFalse);
      expect(passesQualityGate(_r(title: 'Sunset over Silver Springs')), isTrue);
    });

    test('rejects svg/pdf files', () {
      expect(passesQualityGate(_r(mime: 'image/svg+xml')), isFalse);
    });

    test('missing dimensions do not fail the floor', () {
      expect(passesQualityGate(_r(w: null, h: null)), isTrue);
    });
  });

  group('ranking', () {
    test('landscape outranks portrait for the same relevance', () {
      final tokens = significantTokens('Silver Springs');
      final land = rankImage(_r(title: 'Silver Springs', w: 2000, h: 1200),
          nameTokens: tokens);
      final port = rankImage(_r(title: 'Silver Springs', w: 1200, h: 2000),
          nameTokens: tokens);
      expect(land, greaterThan(port));
    });

    test('relevant title outranks irrelevant one', () {
      final tokens = significantTokens('Rainbow Springs');
      final relevant =
          rankImage(_r(title: 'Rainbow Springs headspring'), nameTokens: tokens);
      final irrelevant =
          rankImage(_r(title: 'A generic river photo'), nameTokens: tokens);
      expect(relevant, greaterThan(irrelevant));
    });

    test('public domain scores higher than unknown license', () {
      expect(licenseQuality('CC0'), greaterThan(licenseQuality(null)));
      expect(licenseQuality('Public Domain'), 100);
    });

    test('rankAndFilter drops rejects and sorts best-first', () {
      final input = [
        _r(id: 'logo', title: 'Park logo', w: 3000),
        _r(id: 'small', title: 'Silver Springs', w: 500),
        _r(id: 'good', title: 'Silver Springs State Park', w: 3000, h: 2000),
      ];
      final out = rankAndFilter(input, destinationName: 'Silver Springs State Park');
      expect(out.map((e) => e.id), ['good']);
    });
  });

  group('filters', () {
    final input = [
      _r(id: 'land', title: 'Silver Springs', w: 2000, h: 1200),
      _r(id: 'port', title: 'Silver Springs', w: 1200, h: 2000),
    ];
    test('landscape filter drops portrait', () {
      const f = ImageFilters(orientation: OrientationFilter.landscape);
      final out = f.apply(input, destinationName: 'Silver Springs');
      expect(out.map((e) => e.id), contains('land'));
      expect(out.map((e) => e.id), isNot(contains('port')));
    });
    test('license filter keeps only matching licenses', () {
      final mixed = [
        _r(id: 'cc0', license: 'CC0 (Public Domain)'),
        _r(id: 'bysa', license: 'CC BY-SA 4.0'),
      ];
      const f = ImageFilters(licenseContains: 'cc0');
      final out = f.apply(mixed, destinationName: 'Silver Springs');
      expect(out.map((e) => e.id), ['cc0']);
    });
  });

  group('provider parsing', () {
    test('Openverse parse maps fields + license label', () {
      final body = {
        'results': [
          {
            'id': 'abc',
            'title': 'Rainbow Springs',
            'url': 'https://o/abc.jpg',
            'thumbnail': 'https://o/abc-t.jpg',
            'width': 3000,
            'height': 2000,
            'creator': 'Ansel',
            'license': 'by-sa',
            'license_version': '4.0',
            'license_url': 'https://cc/by-sa',
            'foreign_landing_url': 'https://o/abc',
            'filetype': 'jpg',
            'filesize': 123,
          }
        ]
      };
      final out = OpenverseClient.parse(body);
      expect(out, hasLength(1));
      expect(out.first.source, ImageSource.openverse);
      expect(out.first.license, 'CC BY-SA 4.0');
      expect(out.first.photographer, 'Ansel');
      expect(out.first.orientation, ImageOrientation.landscape);
    });

    test('Wikimedia parse strips File: prefix + HTML in metadata', () {
      final body = {
        'query': {
          'pages': {
            '42': {
              'pageid': 42,
              'title': 'File:Silver_Springs_FL.jpg',
              'imageinfo': [
                {
                  'url': 'https://upload/silver.jpg',
                  'thumburl': 'https://upload/silver-t.jpg',
                  'width': 2400,
                  'height': 1600,
                  'mime': 'image/jpeg',
                  'size': 999,
                  'descriptionurl': 'https://commons/File:Silver',
                  'extmetadata': {
                    'Artist': {'value': '<a href="x">John Smith</a>'},
                    'LicenseShortName': {'value': 'CC BY 2.0'},
                    'LicenseUrl': {'value': 'https://cc/by'},
                  }
                }
              ]
            }
          }
        }
      };
      final out = WikimediaClient.parse(body);
      expect(out, hasLength(1));
      expect(out.first.title, 'Silver Springs FL.jpg');
      expect(out.first.photographer, 'John Smith');
      expect(out.first.license, 'CC BY 2.0');
    });

    test('parsers tolerate empty/garbage bodies', () {
      expect(OpenverseClient.parse(const {}), isEmpty);
      expect(OpenverseClient.parse('nope'), isEmpty);
      expect(WikimediaClient.parse(const {}), isEmpty);
    });
  });

  group('dashboard', () {
    test('counts images, missing heroes, and destinations without photos', () {
      final assets = [
        const MediaAsset(id: '1', publicUrl: 'a', fileSize: 1000),
        const MediaAsset(id: '2', publicUrl: 'b', fileSize: 2000),
      ];
      final dests = [
        MasterLocation(id: 'd1', name: 'Has photo', type: LocationType.spring,
            images: const ['a']),
        MasterLocation(id: 'd2', name: 'No photo', type: LocationType.lake),
      ];
      final d = computeMediaDashboard(assets, dests, now: DateTime(2026));
      expect(d.imagesImported, 2);
      expect(d.storageBytes, 3000);
      expect(d.destinationsWithPhotos, 1);
      expect(d.destinationsWithoutPhotos, 1);
      expect(d.missingHero, 1);
    });
  });
}
