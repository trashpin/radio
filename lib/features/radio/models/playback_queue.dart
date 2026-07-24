import 'package:explorer_os_mobile/features/radio/models/playback_queue_item.dart';

/// An immutable snapshot of the queue's state.
///
/// `QueueManagerService` owns the live mutable queue; this is the read-only view
/// exposed to the UI/consumers (via `getCurrentQueue()`), including any music
/// stashed for resume-after-interruption.
class PlaybackQueue {
  const PlaybackQueue({this.items = const [], this.pausedMusic});

  final List<PlaybackQueueItem> items;
  final PlaybackQueueItem? pausedMusic;

  int get length => items.length;
  bool get isEmpty => items.isEmpty;
  PlaybackQueueItem? get next => items.isEmpty ? null : items.first;
}
