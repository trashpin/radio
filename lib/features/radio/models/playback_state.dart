import 'package:explorer_os_mobile/features/radio/models/playback_queue_item.dart';

/// High-level status of the engine's INTENDED playback (not a real audio
/// player's state).
enum PlaybackStatus { idle, playing, paused, stopped }

/// An immutable snapshot of what the engine currently intends to be happening.
///
/// This is the engine's public, observable state: what's playing, what's queued
/// next, and which music item (if any) is stashed to resume after an
/// interruption. The future UI (and logging/tests) read this; the engine
/// produces a fresh snapshot after every decision. It contains NO audio — only
/// decisions.
class PlaybackState {
  const PlaybackState({
    this.status = PlaybackStatus.idle,
    this.current,
    this.queue = const [],
    this.interruptedItem,
    this.updatedAt,
  });

  final PlaybackStatus status;

  /// The item the engine intends to be playing now.
  final PlaybackQueueItem? current;

  /// Snapshot of upcoming items (highest priority first).
  final List<PlaybackQueueItem> queue;

  /// Music that was paused to allow an interruption, to be resumed afterwards.
  final PlaybackQueueItem? interruptedItem;

  final DateTime? updatedAt;

  bool get hasInterruption => interruptedItem != null;

  PlaybackState copyWith({
    PlaybackStatus? status,
    PlaybackQueueItem? current,
    List<PlaybackQueueItem>? queue,
    PlaybackQueueItem? interruptedItem,
    bool clearCurrent = false,
    bool clearInterruption = false,
    DateTime? updatedAt,
  }) {
    return PlaybackState(
      status: status ?? this.status,
      current: clearCurrent ? null : (current ?? this.current),
      queue: queue ?? this.queue,
      interruptedItem:
          clearInterruption ? null : (interruptedItem ?? this.interruptedItem),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
