import 'package:explorer_os_mobile/features/missions/models/mission_puzzle.dart';
import 'package:flutter_test/flutter_test.dart';

MissionPuzzle _puzzle(List<String> answers) => MissionPuzzle(
      id: 'p1',
      missionId: 'm1',
      prompt: 'What object did Thomas carry?',
      acceptedAnswers: answers,
    );

void main() {
  group('MissionPuzzle.checkAnswer', () {
    test('matches case-insensitively', () {
      final p = _puzzle(['Silver Pocket Watch']);
      expect(p.checkAnswer('silver pocket watch'), isTrue);
      expect(p.checkAnswer('SILVER POCKET WATCH'), isTrue);
    });

    test('trims surrounding whitespace', () {
      final p = _puzzle(['Silver Pocket Watch']);
      expect(p.checkAnswer('  silver pocket watch  '), isTrue);
    });

    test('matches any of several accepted answers', () {
      final p = _puzzle(['silver pocket watch', 'silver watch', 'pocket watch']);
      expect(p.checkAnswer('pocket watch'), isTrue);
      expect(p.checkAnswer('silver watch'), isTrue);
    });

    test('rejects a wrong answer', () {
      final p = _puzzle(['silver pocket watch']);
      expect(p.checkAnswer('gold ring'), isFalse);
    });

    test('rejects an empty answer', () {
      final p = _puzzle(['silver pocket watch']);
      expect(p.checkAnswer(''), isFalse);
      expect(p.checkAnswer('   '), isFalse);
    });
  });
}
