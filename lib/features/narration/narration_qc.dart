/// Pure quality-control helpers for narration scripts. No Flutter/Supabase deps
/// so they can be unit-tested and reused by the server-side generator.
library;

/// Average narration speaking speed (words per minute).
const kSpeakingWpm = 150;

final _wordRe = RegExp(r'[a-zA-Z0-9]+');

/// Number of words in [script].
int wordCount(String? script) =>
    _wordRe.allMatches(script ?? '').length;

/// Estimated speaking time in seconds at [wpm] (default 150).
int speakingSeconds(int words, {int wpm = kSpeakingWpm}) =>
    wpm <= 0 ? 0 : (words / wpm * 60).round();

/// mm:ss for a duration in seconds.
String formatSeconds(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

Set<String> _tokens(String? s) =>
    _wordRe.allMatches((s ?? '').toLowerCase()).map((m) => m.group(0)!).toSet();

/// Jaccard similarity (0..1) of the word sets of [a] and [b] — used as a
/// duplicate score between narration variants (1 = identical vocabulary).
double duplicateScore(String? a, String? b) {
  final ta = _tokens(a), tb = _tokens(b);
  if (ta.isEmpty && tb.isEmpty) return 0;
  final inter = ta.intersection(tb).length;
  final union = ta.union(tb).length;
  return union == 0 ? 0 : inter / union;
}

/// Highest duplicate score of [script] against any sibling in [others].
double maxDuplicateScore(String? script, Iterable<String?> others) {
  var maxV = 0.0;
  for (final o in others) {
    final v = duplicateScore(script, o);
    if (v > maxV) maxV = v;
  }
  return maxV;
}

/// A simple 0..100 readability score (higher = easier), approximated from
/// average sentence length: short, flowing sentences read better aloud.
double readabilityScore(String? script) {
  final text = (script ?? '').trim();
  if (text.isEmpty) return 0;
  final sentences =
      text.split(RegExp(r'[.!?]+')).where((s) => s.trim().isNotEmpty).length;
  final words = wordCount(text);
  if (sentences == 0 || words == 0) return 0;
  final avg = words / sentences; // avg words per sentence
  // ~14 wpsentence is very readable (100); ~34+ is hard (0).
  final score = 100 - ((avg - 14) * 5);
  return score.clamp(0, 100).toDouble();
}
