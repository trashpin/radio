import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_history.dart';

/// Remembers what has already played this session.
///
/// WHY THIS EXISTS: good radio never feels repetitive. The engine consults the
/// history to avoid replaying the same song/narration too soon and to power a
/// "recently played" view later. In-memory for now; can be persisted for
/// cross-session history without changing callers.
class HistoryManager {
  final List<AudioSegment> _history = [];

  /// Most-recent-last list of everything played.
  List<AudioSegment> get all => List.unmodifiable(_history);

  /// Immutable value snapshot (for UI / PlaybackRepository).
  PlaybackHistory get snapshot => PlaybackHistory(items: all);

  void record(AudioSegment segment) => _history.add(segment);

  /// The last [limit] played segments, most recent first.
  List<AudioSegment> recent({int limit = 20}) {
    final start = _history.length - limit;
    final slice = _history.sublist(start < 0 ? 0 : start);
    return slice.reversed.toList(growable: false);
  }

  /// Whether [segmentId] appears within the last [within] played items.
  bool playedRecently(String segmentId, {int within = 10}) {
    return recent(limit: within).any((s) => s.id == segmentId);
  }

  void clear() => _history.clear();
}
