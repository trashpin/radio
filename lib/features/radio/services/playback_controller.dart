import 'package:explorer_os_mobile/features/radio/models/playback_queue_item.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_state.dart';

/// Tracks the engine's INTENDED playback state (current item + status).
///
/// WHY THIS EXISTS: the engine needs a single place that answers "what is
/// supposed to be playing right now, and in what state?". This controller holds
/// that intent — it does NOT touch a real audio player. In production, a thin
/// audio adapter (e.g. `just_audio`) will observe these intents and drive actual
/// sound; the decision logic here stays identical and fully testable offline.
class PlaybackController {
  PlaybackStatus _status = PlaybackStatus.idle;
  PlaybackQueueItem? _current;

  PlaybackStatus get status => _status;
  PlaybackQueueItem? get current => _current;

  /// Marks [item] as the item that should be playing.
  void play(PlaybackQueueItem item) {
    _current = item;
    _status = PlaybackStatus.playing;
  }

  /// Pauses the current item (kept as current).
  void pause() {
    if (_current != null) _status = PlaybackStatus.paused;
  }

  /// Resumes the current item if one is set.
  void resume() {
    if (_current != null) _status = PlaybackStatus.playing;
  }

  /// Marks the current item as finished (nothing playing, ready for the next
  /// decision).
  void complete() {
    _current = null;
    _status = PlaybackStatus.idle;
  }

  /// Stops playback entirely and clears the current item.
  void stop() {
    _current = null;
    _status = PlaybackStatus.stopped;
  }
}
