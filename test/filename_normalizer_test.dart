import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/admin/image_match/filename_normalizer.dart';

void main() {
  test('spec example: Florida Black Bear.jpg → florida_black_bear', () {
    expect(matchKeyFromFilename('Florida Black Bear.jpg'), 'florida_black_bear');
  });

  test('drops extension, lowercases, spaces→underscore', () {
    expect(matchKeyFromFilename('Sand Pine.PNG'), 'sand_pine');
    expect(matchKeyFromFilename('LONGLEAF PINE.jpeg'), 'longleaf_pine');
  });

  test('removes punctuation and collapses duplicate underscores', () {
    expect(matchKeyFromFilename("Red-shouldered  Hawk!!.jpg"),
        'redshouldered_hawk');
    expect(matchKeyFromFilename('Saw   Palmetto___.webp'), 'saw_palmetto');
    expect(matchKeyFromFilename('  Gopher Tortoise .JPG'), 'gopher_tortoise');
  });

  test('normalizeMatchKey matches species names to filenames', () {
    // A species "Saw Palmetto" and a file "saw_palmetto.jpg" normalize equal.
    expect(normalizeMatchKey('Saw Palmetto'),
        matchKeyFromFilename('saw_palmetto.jpg'));
    expect(normalizeMatchKey('Red-shouldered Hawk'),
        matchKeyFromFilename('Red-shouldered Hawk.png'));
  });

  test('handles no-extension and numeric names', () {
    expect(matchKeyFromFilename('Trail Marker 7'), 'trail_marker_7');
  });
}
