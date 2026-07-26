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
}
