import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_queue.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_queue_item.dart';

/// Owns the ordered list of upcoming [PlaybackQueueItem]s and the "paused music"
/// stash used for resume-after-interruption.
///
/// WHY THIS EXISTS: the engine's decisions ultimately manipulate a queue. Rather
/// than scatter list bookkeeping through the engine, all queue mechanics live
/// here behind a small, intention-revealing API. It holds NO audio and makes no
/// policy decisions (the [RadioEngineService] does) — it just maintains order.
///
/// Ordering contract: [insertPriority] keeps higher-priority items ahead of
/// lower-priority ones; [enqueue] appends (used for baseline music);
/// [insertNext] forces an item to the front.
class QueueManagerService {
  final List<PlaybackQueueItem> _queue = [];
  PlaybackQueueItem? _pausedMusic;
  int _counter = 0;

  /// Immutable snapshot of the queue (highest priority first).
  List<PlaybackQueueItem> get items => List.unmodifiable(_queue);

  /// Read-only value snapshot of the whole queue (items + stashed music).
  PlaybackQueue get snapshot =>
      PlaybackQueue(items: items, pausedMusic: _pausedMusic);

  /// Music stashed by [pauseMusic], awaiting [resumeMusic].
  PlaybackQueueItem? get pausedMusic => _pausedMusic;

  bool get isEmpty => _queue.isEmpty;

  PlaybackQueueItem? peekNext() => _queue.isEmpty ? null : _queue.first;

  PlaybackQueueItem _wrap(AudioSegment segment, QueueOrigin origin) =>
      PlaybackQueueItem(
        id: 'q${_counter++}',
        segment: segment,
        origin: origin,
        enqueuedAt: DateTime.now(),
      );

  /// Appends an item to the end of the queue (baseline behavior, e.g. music).
  PlaybackQueueItem enqueue(
    AudioSegment segment, {
    QueueOrigin origin = QueueOrigin.enqueue,
  }) {
    final item = _wrap(segment, origin);
    _queue.add(item);
    return item;
  }

  /// Forces an item to play immediately next (front of the queue).
  PlaybackQueueItem insertNext(
    AudioSegment segment, {
    QueueOrigin origin = QueueOrigin.insertNext,
  }) {
    final item = _wrap(segment, origin);
    _queue.insert(0, item);
    return item;
  }

  /// Inserts an item according to its priority — ahead of the first item with a
  /// strictly lower priority, preserving relative order within a tier (stable).
  PlaybackQueueItem insertPriority(
    AudioSegment segment, {
    QueueOrigin origin = QueueOrigin.insertPriority,
  }) {
    final item = _wrap(segment, origin);
    final index = _queue.indexWhere(
      (existing) => segment.priority.isHigherThan(existing.priority),
    );
    if (index < 0) {
      _queue.add(item);
    } else {
      _queue.insert(index, item);
    }
    return item;
  }

  /// Removes and returns the next item, advancing the queue. Returns null when
  /// empty. (This is how the engine "skips" forward to the next decision.)
  PlaybackQueueItem? skip() => _queue.isEmpty ? null : _queue.removeAt(0);

  /// Removes a specific item by its queue id. Returns true if something was
  /// removed.
  bool remove(String itemId) {
    final before = _queue.length;
    _queue.removeWhere((item) => item.id == itemId);
    return _queue.length != before;
  }

  /// Empties the queue (does not touch the paused-music stash).
  void clear() => _queue.clear();

  /// Stashes the currently-playing music so it can be restored after an
  /// interruption finishes.
  void pauseMusic(PlaybackQueueItem musicItem) => _pausedMusic = musicItem;

  /// Restores stashed music to the front of the queue and returns it (or null
  /// if nothing was paused).
  PlaybackQueueItem? resumeMusic() {
    final music = _pausedMusic;
    _pausedMusic = null;
    if (music != null) _queue.insert(0, music);
    return music;
  }
}
