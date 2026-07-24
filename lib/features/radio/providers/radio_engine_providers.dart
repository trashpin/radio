import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/radio/services/announcement_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/audio_focus_manager.dart';
import 'package:explorer_os_mobile/features/radio/services/audio_player_port.dart';
import 'package:explorer_os_mobile/features/radio/services/radio_audio_service.dart';
import 'package:explorer_os_mobile/features/radio/services/gps_audio_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/history_manager.dart';
import 'package:explorer_os_mobile/features/radio/services/music_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/offline_playback_service.dart';
import 'package:explorer_os_mobile/features/radio/services/playback_controller.dart';
import 'package:explorer_os_mobile/features/radio/services/queue_manager_service.dart';
import 'package:explorer_os_mobile/features/radio/services/radio_engine_service.dart';
import 'package:explorer_os_mobile/features/radio/services/radio_preference_service.dart';
import 'package:explorer_os_mobile/features/radio/services/station_identification_service.dart';
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

final musicSchedulerProvider =
    Provider<MusicScheduler>((ref) => const MusicScheduler());

final stationIdentificationServiceProvider =
    Provider<StationIdentificationService>(
        (ref) => StationIdentificationService());

final audioFocusManagerProvider =
    Provider<AudioFocusManager>((ref) => AudioFocusManager());

final offlinePlaybackServiceProvider =
    Provider<OfflinePlaybackService>((ref) => OfflinePlaybackService());

final radioPreferenceServiceProvider =
    Provider<RadioPreferenceService>((ref) => RadioPreferenceService());

/// The coordinating engine, composed from the singleton services above.
final radioEngineServiceProvider = Provider<RadioEngineService>((ref) {
  final engine = RadioEngineService(
    queue: ref.watch(queueManagerServiceProvider),
    playback: ref.watch(playbackControllerProvider),
    station: ref.watch(stationManagerProvider),
    stories: ref.watch(storySchedulerProvider),
    announcements: ref.watch(announcementSchedulerProvider),
    gps: ref.watch(gpsAudioSchedulerProvider),
    history: ref.watch(historyManagerProvider),
    preferences: ref.watch(userPreferenceManagerProvider),
    musicScheduler: ref.watch(musicSchedulerProvider),
    audioFocus: ref.watch(audioFocusManagerProvider),
    offline: ref.watch(offlinePlaybackServiceProvider),
    stationIds: ref.watch(stationIdentificationServiceProvider),
  );
  ref.onDispose(engine.dispose);
  return engine;
});

/// The production audio output (real `just_audio`). Override with a fake in
/// tests, or an `audio_service`-backed port for full background/CarPlay later.
final audioPlayerPortProvider = Provider<AudioPlayerPort>((ref) {
  final port = JustAudioPlayerPort();
  ref.onDispose(port.dispose);
  return port;
});

/// Bridges the engine's playback intent to real audio. Reading this provider
/// attaches the adapter so decisions become sound.
final radioAudioServiceProvider = Provider<RadioAudioService>((ref) {
  final service = RadioAudioService(
    engine: ref.watch(radioEngineServiceProvider),
    port: ref.watch(audioPlayerPortProvider),
  );
  service.attach();
  ref.onDispose(service.dispose);
  return service;
});
