import 'package:explorer_os_mobile/features/radio/models/playback_queue_item.dart';
import 'package:explorer_os_mobile/features/radio/producer/decision_reason.dart';

/// The Producer's output: the next item to play plus WHY and HOW.
///
/// The Producer does not play audio — it returns this decision. The engine (or a
/// future audio adapter) applies it: play [item], [interrupt] whatever is
/// currently playing if true, and expect music to [resumeMusic] afterwards when
/// applicable. [explanation] is a human-readable rationale for logging/UI.
class PlaybackDecision {
  const PlaybackDecision({
    required this.reason,
    required this.explanation,
    this.item,
    this.interrupt = false,
    this.resumeMusic = false,
  });

  /// The next item to play (null only for [DecisionReason.nothingToPlay]).
  final PlaybackQueueItem? item;
  final DecisionReason reason;
  final bool interrupt;
  final bool resumeMusic;
  final String explanation;

  bool get hasItem => item != null;

  /// Convenience for "the Producer found nothing eligible".
  factory PlaybackDecision.nothing() => const PlaybackDecision(
        reason: DecisionReason.nothingToPlay,
        explanation: 'No eligible audio is available to play.',
      );

  @override
  String toString() => 'PlaybackDecision(${reason.label}: $explanation)';
}
