import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';

/// An immutable snapshot of what has played (most-recent-last).
///
/// `HistoryManager` owns the live history; this value type is the shareable/
/// persistable view (e.g. for a "recently played" UI or the PlaybackRepository).
class PlaybackHistory {
  const PlaybackHistory({this.items = const []});

  final List<AudioSegment> items;

  AudioSegment? get last => items.isEmpty ? null : items.last;

  /// Most-recent-first, capped at [limit].
  List<AudioSegment> recent({int limit = 20}) {
    final start = items.length - limit;
    return items.sublist(start < 0 ? 0 : start).reversed.toList(growable: false);
  }
}
