import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/radio/services/announcement_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/gps_audio_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/history_manager.dart';
import 'package:explorer_os_mobile/features/radio/services/playback_controller.dart';
import 'package:explorer_os_mobile/features/radio/services/queue_manager_service.dart';
import 'package:explorer_os_mobile/features/radio/services/radio_engine_service.dart';
import 'package:explorer_os_mobile/features/radio/services/station_manager.dart';
import 'package:explorer_os_mobile/features/radio/services/story_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/user_preference_manager.dart';

/// Dependency-injection wiring for the Radio Engine.
///
/// Each service is a singleton within the provider scope so they share state
/// (the queue, the playback intent, scheduler counters). Exposing them
/// individually keeps them overridable in tests and reusable elsewhere; the
/// [radioEngineServiceProvider] composes them into the coordinating brain.

final queueManagerServiceProvider =
    Provider<QueueManagerService>((ref) => QueueManagerService());

final playbackControllerProvider =
    Provider<PlaybackController>((ref) => PlaybackController());

final stationManagerProvider =
    Provider<StationManager>((ref) => StationManager());

final storySchedulerProvider =
    Provider<StoryScheduler>((ref) => StoryScheduler());

final announcementSchedulerProvider =
    Provider<AnnouncementScheduler>((ref) => AnnouncementScheduler());

final gpsAudioSchedulerProvider =
    Provider<GPSAudioScheduler>((ref) => GPSAudioScheduler());

final historyManagerProvider =
    Provider<HistoryManager>((ref) => HistoryManager());

final userPreferenceManagerProvider =
    Provider<UserPreferenceManager>((ref) => UserPreferenceManager());

/// The coordinating engine, composed from the singleton services above.
final radioEngineServiceProvider = Provider<RadioEngineService>((ref) {
  return RadioEngineService(
    queue: ref.watch(queueManagerServiceProvider),
    playback: ref.watch(playbackControllerProvider),
    station: ref.watch(stationManagerProvider),
    stories: ref.watch(storySchedulerProvider),
    announcements: ref.watch(announcementSchedulerProvider),
    gps: ref.watch(gpsAudioSchedulerProvider),
    history: ref.watch(historyManagerProvider),
    preferences: ref.watch(userPreferenceManagerProvider),
  );
});
