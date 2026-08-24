import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/missions/services/arrival_confirmer.dart';

void main() {
  group('ArrivalConfirmer', () {
    test('does not confirm on a single inside fix', () {
      final confirmer = ArrivalConfirmer();
      expect(confirmer.confirm('stop-1', true), isFalse);
    });

    test('confirms once requiredStreak consecutive inside fixes are seen', () {
      final confirmer = ArrivalConfirmer(requiredStreak: 2);
      expect(confirmer.confirm('stop-1', true), isFalse);
      expect(confirmer.confirm('stop-1', true), isTrue);
    });

    test('a single noisy outside fix resets the streak', () {
      final confirmer = ArrivalConfirmer(requiredStreak: 2);
      expect(confirmer.confirm('stop-1', true), isFalse);
      expect(confirmer.confirm('stop-1', false), isFalse);
      expect(confirmer.confirm('stop-1', true), isFalse);
      expect(confirmer.confirm('stop-1', true), isTrue);
    });

    test('a car passing near the destination without stopping never confirms', () {
      final confirmer = ArrivalConfirmer(requiredStreak: 2);
      expect(confirmer.confirm('stop-1', true), isFalse);
      expect(confirmer.confirm('stop-1', false), isFalse);
      expect(confirmer.confirm('stop-1', false), isFalse);
    });

    test('tracks each stop independently', () {
      final confirmer = ArrivalConfirmer(requiredStreak: 2);
      expect(confirmer.confirm('stop-1', true), isFalse);
      expect(confirmer.confirm('stop-2', true), isFalse);
      expect(confirmer.confirm('stop-2', true), isTrue);
      // stop-1's streak is untouched by stop-2's fixes.
      expect(confirmer.confirm('stop-1', true), isTrue);
    });

    test('stays confirmed on continued inside fixes after first confirming', () {
      final confirmer = ArrivalConfirmer(requiredStreak: 2);
      confirmer.confirm('stop-1', true);
      confirmer.confirm('stop-1', true);
      expect(confirmer.confirm('stop-1', true), isTrue);
    });
  });
}
