import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/narration/narration_qc.dart';
import 'package:explorer_os_mobile/features/narration/models/destination_narration.dart';

void main() {
  test('wordCount counts words, ignoring punctuation/whitespace', () {
    expect(wordCount('Hello, world!'), 2);
    expect(wordCount('  one   two\nthree '), 3);
    expect(wordCount(''), 0);
    expect(wordCount(null), 0);
  });

  test('speakingSeconds uses 150 wpm', () {
    expect(speakingSeconds(150), 60); // 150 words -> 60s
    expect(speakingSeconds(75), 30);
    expect(speakingSeconds(0), 0);
    expect(speakingSeconds(300, wpm: 150), 120);
  });

  test('formatSeconds renders mm:ss', () {
    expect(formatSeconds(60), '1:00');
    expect(formatSeconds(9), '0:09');
    expect(formatSeconds(125), '2:05');
  });

  test('duplicateScore is 1 for identical, lower for different', () {
    expect(duplicateScore('the quick brown fox', 'the quick brown fox'), 1.0);
    expect(duplicateScore('a b c d', 'e f g h'), 0.0);
    final partial = duplicateScore('the quick brown fox', 'the slow brown bear');
    expect(partial, greaterThan(0.0));
    expect(partial, lessThan(1.0));
  });

  test('maxDuplicateScore picks the closest sibling', () {
    final v = maxDuplicateScore('the quick brown fox',
        ['totally different words here', 'the quick brown fox jumped']);
    expect(v, greaterThan(0.6));
  });

  test('readabilityScore rewards shorter sentences', () {
    final easy = readabilityScore('Come on in. It is lovely here. Enjoy the view.');
    final hard = readabilityScore(
        'This is an extraordinarily long and winding sentence that keeps going '
        'well past the point where any listener could comfortably follow it '
        'without losing the thread entirely and giving up in frustration.');
    expect(easy, greaterThan(hard));
    expect(easy, inInclusiveRange(0, 100));
  });

  test('script type catalog has all 25 types with variation counts', () {
    expect(NarrationScriptType.values.length, 25);
    expect(NarrationScriptType.arrival.variations, 3);
    expect(NarrationScriptType.mainHistory.variations, 5);
    expect(NarrationScriptType.funFacts.variations, 5);
    expect(NarrationScriptType.kidsVersion.variations, 3);
    expect(NarrationScriptType.fromDb('wildlife'), NarrationScriptType.wildlife);
    expect(NarrationScriptType.fromDb('nope'), isNull);
  });
}
