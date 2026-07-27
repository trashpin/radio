import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/admin/csv/csv_import_logic.dart';

void main() {
  final targets = buildCsvTargets();
  CsvTarget targetNamed(String label) =>
      targets.firstWhere((t) => t.label == label);

  test('all brief content types have a target', () {
    const expected = [
      'Wildlife',
      'Birds',
      'Plants',
      'Trees',
      'Wildflowers',
      'Trails',
      'Points of Interest',
      'Stories',
      'Historical Events',
      'Campgrounds',
      'Songs (metadata only)',
    ];
    for (final label in expected) {
      expect(targets.any((t) => t.label == label), isTrue, reason: label);
    }
  });

  test('autoMapColumns matches by normalized name (case/space/underscore)', () {
    final plants = targetNamed('Plants');
    final headers = ['Common Name', 'scientific_name', 'Notes', 'HERO IMAGE'];
    final map = autoMapColumns(headers, plants);
    expect(map['common_name'], 'Common Name');
    expect(map['scientific_name'], 'scientific_name');
    expect(map['hero_image'], 'HERO IMAGE');
    // No sensible match → null (skip).
    expect(map['diet'], isNull);
  });

  test('buildRecord maps values, applies defaults, and derives match_key', () {
    final plants = targetNamed('Plants');
    final headers = ['Common Name', 'scientific_name'];
    final mapping = autoMapColumns(headers, plants);
    final rec =
        buildRecord(plants, headers, ['Saw Palmetto', 'Serenoa repens'], mapping);
    expect(rec, isNotNull);
    expect(rec!['common_name'], 'Saw Palmetto');
    expect(rec['scientific_name'], 'Serenoa repens');
    expect(rec['category'], 'plants'); // default
    expect(rec['published'], true); // default
    expect(rec['match_key'], 'saw_palmetto'); // derived for image matching
  });

  test('buildRecord returns null when a required field is missing', () {
    final plants = targetNamed('Plants');
    final headers = ['Common Name', 'scientific_name'];
    final mapping = autoMapColumns(headers, plants);
    final rec = buildRecord(plants, headers, ['', 'Serenoa repens'], mapping);
    expect(rec, isNull);
  });

  test('numeric columns are parsed to numbers', () {
    final poi = targetNamed('Points of Interest');
    final headers = ['name', 'latitude', 'longitude', 'trigger_radius_m'];
    final mapping = autoMapColumns(headers, poi);
    final rec = buildRecord(
        poi, headers, ['Juniper Springs', '29.18', '-81.71', '150'], mapping);
    expect(rec, isNotNull);
    expect(rec!['latitude'], 29.18);
    expect(rec['longitude'], -81.71);
    expect(rec['trigger_radius_m'], 150);
    expect(rec['name'], 'Juniper Springs');
  });

  test('generatedIdColumn gets a UUID (stories.story_id)', () {
    final stories = targetNamed('Stories');
    final headers = ['title'];
    final mapping = autoMapColumns(headers, stories);
    final rec = buildRecord(stories, headers, ['The Springs of Ocala'], mapping,
        uuid: () => 'fixed-uuid');
    expect(rec, isNotNull);
    expect(rec!['story_id'], 'fixed-uuid');
    expect(rec['title'], 'The Springs of Ocala');
    expect(rec['published'], true);
    // story_category is NOT NULL in the DB → must always be set.
    expect(rec['story_category'], 'history');
  });

  test('requiredMapped reflects whether required columns are mapped', () {
    final songs = targetNamed('Songs (metadata only)');
    final headers = ['artist', 'genre'];
    final unmapped = autoMapColumns(headers, songs);
    expect(requiredMapped(songs, unmapped), isFalse); // no title column
    final withTitle = {...unmapped, 'title': 'artist'};
    expect(requiredMapped(songs, withTitle), isTrue);
  });

  test('songs import needs no generated id (table default) and sets defaults',
      () {
    final songs = targetNamed('Songs (metadata only)');
    final headers = ['title', 'artist', 'duration'];
    final mapping = autoMapColumns(headers, songs);
    final rec = buildRecord(songs, headers, ['Trail Groove', 'DJ B', '212'], mapping);
    expect(rec, isNotNull);
    expect(rec!['category'], 'music');
    expect(rec['is_active'], true);
    expect(rec['duration'], 212);
    expect(rec.containsKey('story_id'), isFalse);
  });

  group('Destinations passthrough importer', () {
    test('Destinations target exists and is direct-mapping (passthrough)', () {
      final dest = targetNamed('Destinations');
      expect(dest.table, 'destinations');
      expect(dest.passthrough, isTrue);
    });

    test('passthroughKey snake_cases arbitrary headers', () {
      expect(passthroughKey('Destination Type'), 'destination_type');
      expect(passthroughKey('State/Province'), 'state_province');
      expect(passthroughKey('  destination_code '), 'destination_code');
      expect(passthroughKey('Latitude'), 'latitude');
    });

    test('coerceCsvValue coerces numbers/bools but never rejects text', () {
      expect(coerceCsvValue('USA'), 'USA');
      expect(coerceCsvValue('State Park'), 'State Park');
      expect(coerceCsvValue('29.1872'), 29.1872);
      expect(coerceCsvValue('150'), 150);
      expect(coerceCsvValue('true'), true);
      expect(coerceCsvValue('False'), false);
      expect(coerceCsvValue('   '), isNull); // empty → omit
    });

    test('buildRecord maps every column directly and accepts USA / State Park',
        () {
      final dest = targetNamed('Destinations');
      final headers = [
        'name',
        'destination_type',
        'country',
        'state_province',
        'latitude',
        'longitude',
        'published',
      ];
      final rec = buildRecord(
        dest,
        headers,
        ['Silver Springs', 'State Park', 'USA', 'Florida', '29.2', '-82.05', 'true'],
        const {}, // mapping ignored for passthrough
      );
      expect(rec, isNotNull);
      expect(rec!['name'], 'Silver Springs');
      expect(rec['destination_type'], 'State Park'); // not rejected
      expect(rec['country'], 'USA'); // not rejected
      expect(rec['state_province'], 'Florida');
      expect(rec['latitude'], 29.2);
      expect(rec['published'], true);
    });

    test('buildRecord does not require fields; only skips fully-empty rows', () {
      final dest = targetNamed('Destinations');
      final headers = ['name', 'country'];
      // No name provided, but the row is not blocked — the DB validates instead.
      final rec = buildRecord(dest, headers, ['', 'USA'], const {});
      expect(rec, isNotNull);
      expect(rec!['country'], 'USA');
      expect(rec.containsKey('name'), isFalse);
      // Fully-empty row is skipped.
      expect(buildRecord(dest, headers, ['', ''], const {}), isNull);
    });

    test('requiredMapped is always true for passthrough (no client-side gate)',
        () {
      final dest = targetNamed('Destinations');
      expect(requiredMapped(dest, const {}), isTrue);
    });

    test('Destinations uses destination_code business key + auto destination_id',
        () {
      final dest = targetNamed('Destinations');
      expect(dest.upsertKey, 'destination_code');
      expect(dest.autoUuidColumn, 'destination_id');
    });

    test('destination_id auto-generates when blank; never null', () {
      final dest = targetNamed('Destinations');
      final headers = ['name', 'destination_code', 'destination_id'];
      final rec = buildRecord(
          dest, headers, ['Blue Spring', 'FLSP9', ''], const {},
          uuid: () => 'generated-uuid');
      expect(rec, isNotNull);
      expect(rec!['destination_id'], 'generated-uuid');
      expect(rec['destination_id'], isNotNull);
    });

    test('a supplied destination_id is kept as-is', () {
      final dest = targetNamed('Destinations');
      final headers = ['name', 'destination_code', 'destination_id'];
      final rec = buildRecord(dest, headers,
          ['Blue Spring', 'FLSP9', 'existing-id-123'], const {},
          uuid: () => 'generated-uuid');
      expect(rec!['destination_id'], 'existing-id-123');
    });

    test('destination_id generated even when the column is absent from the CSV',
        () {
      final dest = targetNamed('Destinations');
      final rec = buildRecord(dest, ['name', 'destination_code'],
          ['Blue Spring', 'FLSP9'], const {}, uuid: () => 'gen');
      expect(rec!['destination_id'], 'gen');
    });
  });
}
