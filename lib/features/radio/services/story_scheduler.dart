import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';

/// Decides WHEN a story narration should be woven into the stream.
///
/// WHY THIS EXISTS: narrations shouldn't play back-to-back or at random — they
/// should appear at a comfortable cadence between music. This scheduler holds a
/// supply of pending narration segments and a cadence (from the station's
/// rules) and releases one narration every N music tracks. It only DECIDES;
/// the engine performs the actual queue insertion.
class StoryScheduler {
  final List<AudioSegment> _pending = [];
  int _everyTracks = 3;
  int _sinceLast = 0;

  bool get hasPending => _pending.isNotEmpty;

  /// Configures the cadence and the narration supply for the current station.
  void configure({
    required int everyTracks,
    required List<AudioSegment> narrations,
  }) {
    _everyTracks = everyTracks < 1 ? 1 : everyTracks;
    _pending
      ..clear()
      ..addAll(narrations);
    _sinceLast = 0;
  }

  /// Call after each music track finishes. Returns a narration segment when one
  /// is due, otherwise null.
  AudioSegment? onMusicPlayed() {
    if (_pending.isEmpty) return null;
    _sinceLast++;
    if (_sinceLast >= _everyTracks) {
      _sinceLast = 0;
      return _pending.removeAt(0);
    }
    return null;
  }
}
