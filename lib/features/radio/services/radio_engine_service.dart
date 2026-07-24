import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_queue_item.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_state.dart';
import 'package:explorer_os_mobile/features/radio/services/announcement_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/gps_audio_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/history_manager.dart';
import 'package:explorer_os_mobile/features/radio/services/playback_controller.dart';
import 'package:explorer_os_mobile/features/radio/services/queue_manager_service.dart';
import 'package:explorer_os_mobile/features/radio/services/station_manager.dart';
import 'package:explorer_os_mobile/features/radio/services/story_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/user_preference_manager.dart';

/// The BRAIN of Explorer Radio — an intelligent decision engine, NOT an audio
/// player.
///
/// It coordinates every other service to answer four questions continuously:
///   • what should play next?      → [playNext] / [_takeNext]
///   • what should interrupt?      → [requestInterruption]
///   • when does narration begin?  → schedulers inject after music ([onSegmentCompleted])
///   • when does music resume?     → `resumeAfter` + the paused-music stash
///
/// It never produces sound. It manipulates the [QueueManagerService] and updates
/// the [PlaybackController]'s intended state; a future audio adapter observes
/// that intent and does the actual playing. Because all inputs are injected and
/// all logic is synchronous, the engine is fully unit-testable offline.
///
/// Typical lifecycle (driven by the controller, which loads content):
///   1. content is loaded and handed to [StationManager]/schedulers
///   2. [start] kicks off the first item
///   3. the audio layer reports completion → [onSegmentCompleted]
///   4. external events (alerts, future GPS) call [requestInterruption]
class RadioEngineService {
  RadioEngineService({
    required this.queue,
    required this.playback,
    required this.station,
    required this.stories,
    required this.announcements,
    required this.gps,
    required this.history,
    required this.preferences,
  });

  final QueueManagerService queue;
  final PlaybackController playback;
  final StationManager station;
  final StoryScheduler stories;
  final AnnouncementScheduler announcements;
  final GPSAudioScheduler gps;
  final HistoryManager history;
  final UserPreferenceManager preferences;

  /// A fresh, immutable snapshot of what the engine intends right now.
  PlaybackState get state => PlaybackState(
        status: playback.status,
        current: playback.current,
        queue: queue.items,
        interruptedItem: queue.pausedMusic,
        updatedAt: DateTime.now(),
      );

  /// Starts playback by choosing and playing the first item.
  void start() => playNext();

  /// Chooses the next item and marks it as playing (or stops if nothing is
  /// available).
  void playNext() {
    final next = _takeNext();
    if (next == null) {
      playback.stop();
      return;
    }
    playback.play(next);
  }

  /// The core "what plays next" decision:
  ///   1. serve the highest-priority queued item, else
  ///   2. fall back to the station's next music track (respecting preferences).
  PlaybackQueueItem? _takeNext() {
    final queued = queue.skip();
    if (queued != null) return queued;

    final music = station.nextMusicSegment();
    if (music == null) return null;
    if (!preferences.allowsTags(music.tags)) return _takeNext();

    // Route the fallback music through the queue so it becomes a real item.
    queue.enqueue(music, origin: QueueOrigin.enqueue);
    return queue.skip();
  }

  /// Called by the audio layer when the current segment finishes.
  ///
  /// Handles: recording history, resuming paused music after an interruption,
  /// and letting the schedulers weave in narration/announcements after music.
  void onSegmentCompleted() {
    final finished = playback.current;
    if (finished != null) {
      history.record(finished.segment);

      // If an interruption just ended, restore the music it displaced.
      if (finished.segment.resumeAfter) {
        queue.resumeMusic();
      }

      // After a music track, schedulers may inject scheduled content.
      if (finished.segment.type == AudioSegmentType.music) {
        _injectScheduledContent();
      }
    }

    playback.complete();
    playNext();
  }

  /// Requests that [segment] interrupt playback (safety/emergency alerts,
  /// scheduled announcements, and — later — GPS narration).
  ///
  /// Interrupts immediately only if something interruptible of lower priority is
  /// playing; otherwise the item is queued by priority and plays when reached.
  void requestInterruption(AudioSegment segment) {
    final current = playback.current;
    final canInterruptNow = current != null &&
        current.segment.interruptible &&
        segment.priority.isHigherThan(current.segment.priority);

    if (canInterruptNow) {
      // Stash displaced music so it resumes after the interruption ends.
      if (current.segment.type == AudioSegmentType.music) {
        queue.pauseMusic(current);
      }
      playback.complete();
      queue.insertPriority(segment, origin: QueueOrigin.insertPriority);
      playNext();
    } else {
      queue.insertPriority(segment, origin: QueueOrigin.insertPriority);
    }
  }

  /// Skips the current item and advances to the next decision.
  void skip() {
    playback.complete();
    playNext();
  }

  /// Pauses/resumes the current item (intent only).
  void pause() => playback.pause();
  void resume() => playback.resume();

  /// Stops the engine entirely.
  void stop() {
    playback.stop();
    queue.clear();
  }

  void _injectScheduledContent() {
    final due = <AudioSegment>[];
    if (preferences.narrationsEnabled) {
      final narration = stories.onMusicPlayed();
      if (narration != null) due.add(narration);
    }
    if (preferences.announcementsEnabled) {
      final announcement = announcements.onMusicPlayed();
      if (announcement != null) due.add(announcement);
    }

    for (final segment in due) {
      if (!preferences.allowsTags(segment.tags)) continue;
      final origin = segment.type == AudioSegmentType.narration
          ? QueueOrigin.scheduledStory
          : QueueOrigin.scheduledAnnouncement;
      queue.insertPriority(segment, origin: origin);
    }
  }
}
