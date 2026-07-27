import 'dart:math' as math;

/// The single, mutually-exclusive high-level state of the [PlaybackManager].
///
/// Only ONE of these is active at any time — it is the "what is the engine
/// doing right now" answer that the UI and debug panel read.
enum PlaybackState {
  idle,
  playingMusic,
  playingNarration,
  paused,
  buffering,
  stopped,
  error,
}

/// Per-channel status (music channel and narration channel each have one).
///
/// The engine drives two independent audio outputs so music can be ducked and
/// resumed around a narration; this tracks each one separately.
enum ChannelStatus { idle, playing, paused, stopped, error }

/// The kind of audio a queue item represents.
///
/// Every type except [music] is an "announcement" that plays on the narration
/// channel and interrupts music. Each type carries a default [priority] from
/// the fixed ExplorerOS ladder.
enum PlaybackItemType {
  music(10),
  route(50),
  narration(60),
  // `departure` is not in the brief's explicit ladder; it is placed just below
  // `arrival` since a departure cue is slightly less urgent than an arrival.
  departure(75),
  poi(70),
  arrival(80),
  safety(90),
  emergency(100);

  const PlaybackItemType(this.priority);

  /// Default priority for this type (higher wins / interrupts).
  final int priority;

  /// Music plays on the music channel; everything else on the narration
  /// channel and interrupts music.
  bool get isMusic => this == PlaybackItemType.music;
}

/// Lifecycle status of a single queue item.
enum PlaybackItemStatus { queued, playing, finished, failed, cancelled }

int _idCounter = 0;

/// An immutable request to play one piece of audio.
///
/// Items flow through the queue and the currently-playing slots. They are
/// immutable; the manager tracks progress by swapping in [copyWith] copies with
/// an updated [status], which keeps event payloads point-in-time correct.
class PlaybackItem {
  PlaybackItem({
    String? id,
    required this.type,
    required this.title,
    required this.audioUrl,
    this.duration,
    Map<String, Object?> metadata = const {},
    int? priority,
    this.status = PlaybackItemStatus.queued,
    DateTime? createdAt,
  })  : id = id ?? _generateId(),
        priority = priority ?? type.priority,
        metadata = Map.unmodifiable(metadata),
        createdAt = createdAt ?? DateTime.now();

  final String id;
  final PlaybackItemType type;
  final int priority;
  final String title;
  final String audioUrl;
  final Duration? duration;
  final Map<String, Object?> metadata;
  final PlaybackItemStatus status;
  final DateTime createdAt;

  bool get isMusic => type.isMusic;

  PlaybackItem copyWith({
    PlaybackItemStatus? status,
    int? priority,
    Duration? duration,
  }) {
    return PlaybackItem(
      id: id,
      type: type,
      title: title,
      audioUrl: audioUrl,
      duration: duration ?? this.duration,
      metadata: metadata,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }

  static String _generateId() {
    _idCounter = (_idCounter + 1) & 0x7fffffff;
    final rand = math.Random().nextInt(1 << 20);
    return 'pi_${DateTime.now().microsecondsSinceEpoch}_${_idCounter}_$rand';
  }

  @override
  String toString() =>
      'PlaybackItem($title, ${type.name}, p$priority, ${status.name})';
}

/// The set of lifecycle events the manager emits on its [PlaybackManager.events]
/// stream. Mirrors the brief's event list one-to-one.
enum PlaybackEventType {
  playbackStarted,
  playbackPaused,
  playbackStopped,
  playbackFinished,
  queueUpdated,
  musicStarted,
  narrationStarted,
  narrationFinished,
  errorOccurred,
}

/// A single emitted event with an optional related [item] and [message].
class PlaybackEvent {
  PlaybackEvent(this.type, {this.item, this.message, DateTime? at})
      : at = at ?? DateTime.now();

  final PlaybackEventType type;
  final PlaybackItem? item;
  final String? message;
  final DateTime at;

  @override
  String toString() {
    final parts = <String>[type.name];
    if (item != null) parts.add(item!.title);
    if (message != null) parts.add(message!);
    return parts.join(' · ');
  }
}

/// An immutable snapshot of everything the debug panel / UI needs to render.
///
/// The manager publishes a fresh snapshot on every state change via
/// [PlaybackManager.snapshots].
class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.state,
    this.currentTrack,
    this.musicTrack,
    this.narrationTrack,
    required this.queueLength,
    this.queue = const [],
    this.currentPriority,
    required this.volume,
    required this.muted,
    required this.musicStatus,
    required this.narrationStatus,
    this.lastEvent,
  });

  final PlaybackState state;

  /// The audible "now playing" item (narration wins over music when active).
  final PlaybackItem? currentTrack;
  final PlaybackItem? musicTrack;
  final PlaybackItem? narrationTrack;

  final int queueLength;
  final List<PlaybackItem> queue;
  final int? currentPriority;
  final double volume;
  final bool muted;
  final ChannelStatus musicStatus;
  final ChannelStatus narrationStatus;
  final PlaybackEvent? lastEvent;
}
