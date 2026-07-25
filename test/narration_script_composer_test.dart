import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/discovery/models/species.dart';
import 'package:explorer_os_mobile/features/narration/models/narration_type.dart';
import 'package:explorer_os_mobile/features/narration/services/narration_script_composer.dart';

const _composer = NarrationScriptComposer();

Species _bear() => const Species(
      id: '1',
      category: 'animals',
      commonName: 'Florida Black Bear',
      scientificName: 'Ursus americanus floridanus',
      description: 'A subspecies of the American black bear found in Florida.',
      color: 'black',
      diet: 'omnivore — berries, acorns, insects',
      behavior: 'mostly solitary and shy',
      conservationStatus: 'least concern',
      safetyInfo: 'never approach or feed bears',
      funFacts: 'they can smell food from over a mile away',
    );

void main() {
  test('standard script includes intro, id, safety, conservation, closing', () {
    final script = _composer.composeForSpecies(_bear());
    expect(script, contains('Florida Black Bear'));
    expect(script, contains('Ursus americanus floridanus')); // identification
    expect(script.toLowerCase(), contains('safety'));
    expect(script.toLowerCase(), contains('conservation status'));
    expect(script.toLowerCase(), contains('keep discovering')); // closing
    expect(script, contains('\n\n')); // multi-section
  });

  test('kids guide uses a playful intro and skips dense description', () {
    final script =
        _composer.composeForSpecies(_bear(), type: NarrationType.kidsGuide);
    expect(script, contains('junior ranger'));
    // Kids style omits the encyclopedic description paragraph.
    expect(script, isNot(contains('subspecies of the American black bear')));
  });

  test('safety information style leads with safety framing', () {
    final script = _composer.composeForSpecies(_bear(),
        type: NarrationType.safetyInformation);
    expect(script.toLowerCase(), contains('what you should know'));
    expect(script.toLowerCase(), contains('never approach or feed bears'));
  });

  test('word count and duration estimate are sane (30s–2min target)', () {
    final script = _composer.composeForSpecies(_bear(),
        type: NarrationType.deepDive);
    final words = _composer.wordCount(script);
    final secs = _composer.estimateSeconds(script);
    expect(words, greaterThan(20));
    expect(secs, (words / 2.5).round());
  });

  test('handles a sparse record without crashing', () {
    const sparse = Species(id: '2', category: 'plants', commonName: 'Wiregrass');
    final script = _composer.composeForSpecies(sparse);
    expect(script, contains('Wiregrass'));
    expect(_composer.wordCount(script), greaterThan(0));
  });
}
