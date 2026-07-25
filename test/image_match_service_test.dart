import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/admin/image_match/image_match_service.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';

const _service = ImageMatchService();

Species _sp(String id, String name, {String? image}) =>
    Species(id: id, category: 'plants', commonName: name, heroImage: image);

void main() {
  final species = [
    _sp('1', 'Saw Palmetto', image: 'https://x/saw.jpg'), // has image
    _sp('2', 'Sand Pine'),
    _sp('3', 'Longleaf Pine'),
    _sp('4', 'Longleaf Pine'), // duplicate name → multi-match
  ];

  test('single match with existing image is skipped unless replace', () {
    final r = _service.classify(
        [ImageCandidate(filename: 'Saw Palmetto.jpg')], species);
    expect(r.rows.single.status, MatchStatus.skipped);
    expect(r.skipped, 1);

    final r2 = _service.classify(
        [ImageCandidate(filename: 'Saw Palmetto.jpg')], species,
        replaceExisting: true);
    expect(r2.rows.single.status, MatchStatus.matched);
    expect(r2.matched, 1);
  });

  test('single match without image is matched', () {
    final r =
        _service.classify([ImageCandidate(filename: 'Sand Pine.png')], species);
    expect(r.rows.single.status, MatchStatus.matched);
    expect(r.rows.single.species!.commonName, 'Sand Pine');
  });

  test('multiple matches flagged for selection', () {
    final r = _service
        .classify([ImageCandidate(filename: 'Longleaf Pine.jpeg')], species);
    expect(r.rows.single.status, MatchStatus.multiMatch);
    expect(r.rows.single.matches.length, 2);
  });

  test('no match goes to unmatched queue', () {
    final r = _service
        .classify([ImageCandidate(filename: 'Florida Black Bear.jpg')], species);
    expect(r.rows.single.status, MatchStatus.unmatched);
    expect(r.unmatched, 1);
  });

  test('report counts aggregate a mixed batch', () {
    final r = _service.classify([
      ImageCandidate(filename: 'Saw Palmetto.jpg'), // skipped
      ImageCandidate(filename: 'Sand Pine.png'), // matched
      ImageCandidate(filename: 'Longleaf Pine.jpg'), // multi
      ImageCandidate(filename: 'Bald Eagle.png'), // unmatched
    ], species);
    expect(r.total, 4);
    expect(r.skipped, 1);
    expect(r.matched, 1);
    expect(r.multiMatch, 1);
    expect(r.unmatched, 1);
  });

  test('storage path is organized by park/category', () {
    final path = _service.storagePath(
        'Ocala', 'Plants', ImageCandidate(filename: 'Saw Palmetto.jpg'));
    expect(path, 'ocala/plants/saw_palmetto.jpg');
  });
}
