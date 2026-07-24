import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';

/// Records WHY an item entered the queue — useful for debugging the engine's
/// decisions and for analytics/history.
enum QueueOrigin {
  enqueue,
  insertNext,
  insertPriority,
  scheduledStory,
  scheduledAnnouncement,
  gps,
  resume,
}

/// A wrapper that pairs an [AudioSegment] with queue bookkeeping.
///
/// The queue holds [PlaybackQueueItem]s (not raw segments) so each entry has a
/// stable, unique queue [id] (for targeted removal), its [origin], and the time
/// it was enqueued. Priority is delegated to the underlying segment.
class PlaybackQueueItem {
  const PlaybackQueueItem({
    required this.id,
    required this.segment,
    required this.origin,
    required this.enqueuedAt,
  });

  final String id;
  final AudioSegment segment;
  final QueueOrigin origin;
  final DateTime enqueuedAt;

  PlaybackPriority get priority => segment.priority;
}
