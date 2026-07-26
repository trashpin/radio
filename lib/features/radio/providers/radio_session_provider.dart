import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/error/app_exception.dart';
import 'package:explorer_os_mobile/features/destinations/data/destination_repository.dart';
import 'package:explorer_os_mobile/features/dj/data/dj_clip_repository.dart';
import 'package:explorer_os_mobile/features/media/data/media_repository.dart';
import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/providers/radio_engine_providers.dart';
import 'package:explorer_os_mobile/features/radio/providers/stations_provider.dart';
import 'package:explorer_os_mobile/features/radio/repositories/song_repository.dart';
import 'package:explorer_os_mobile/features/radio/services/radio_scheduler.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/shared/models/radio_station.dart';

/// Bootstraps a listening session: attaches audio output, derives the active
/// station from Base44 content (a destination that has audio `media`), loads
/// that destination's audio playlist, and hands it to the engine WITHOUT
/// auto-playing (the UI's Play button starts it, per web autoplay rules).
///
/// This is the glue that makes the radio audible against the real Base44
/// schema: `destinations` → station, `media` (audio in the `mp3` bucket) →
/// playlist → engine → audio adapter. Returns the active station for the UI;
/// surfaces a friendly error when there is no audio content yet.
final radioSessionProvider = FutureProvider<RadioStation>((ref) async {
  // Attach the audio adapter (engine intent → real sound via just_audio).
  ref.read(radioAudioServiceProvider);

  // Load any pre-generated DJ voice clips so the DJ speaks in-character between
  // songs (falls back to TTS when none exist yet).
  try {
    final clips = await ref.read(djClipRepositoryProvider).all();
    if (clips.isNotEmpty) {
      ref.read(radioEngineServiceProvider).djBanter.setClips(clips);
    }
  } catch (_) {}

  final media = ref.read(mediaRepositoryProvider);

  // If the user picked a station from the Stations screen, honor it; load its
  // audio from the linked destination's media (empty for curated stations
  // until they have content).
  final songRepo = ref.read(songRepositoryProvider);
  final selected = ref.watch(selectedStationProvider);
  if (selected != null) {
    // Prefer dynamic songs uploaded via the admin (songs table), matched by
    // station name; fall back to the linked destination's media, then any
    // active songs so playback always has content.
    var songs = await songRepo.activeSongs(station: selected.name);
    if (songs.isEmpty && selected.destinationId != null) {
      songs = await media.songsForDestination(selected.destinationId!);
    }
    if (songs.isEmpty) songs = await songRepo.activeSongs();
    ref
        .read(radioEngineServiceProvider)
        .changeStation(selected, songs: songs, autoPlay: false);
    ref.read(radioEngineControllerProvider);
    _attachScheduler(ref, selected);
    return selected;
  }

  final destinations =
      await ref.watch(destinationRepositoryProvider).fetchDestinations();
  if (destinations.isEmpty) {
    throw const AppException(
      'No destinations are available yet. Add a destination (and audio media) '
      'in Base44 to start listening.',
      type: AppExceptionType.notFound,
    );
  }

  // Prefer a destination that actually has audio media so the station can play.
  final withAudio = await media.destinationIdsWithAudio();
  final destination = destinations.firstWhere(
    (d) => withAudio.contains(d.id),
    orElse: () => destinations.first,
  );

  final station = RadioStation.fromDestination(destination);
  // Dynamic playlist: prefer admin-uploaded songs (songs table), fall back to
  // the destination's media audio.
  var songs = await songRepo.activeSongs();
  if (songs.isEmpty) songs = await media.songsForDestination(destination.id);

  ref
      .read(radioEngineServiceProvider)
      .changeStation(station, songs: songs, autoPlay: false);

  // Ensure the controller is alive so it reflects engine events in the UI.
  ref.read(radioEngineControllerProvider);
  _attachScheduler(ref, station);

  return station;
});

/// Starts the programming scheduler for the session: it injects due
/// announcements (safety/wildlife with audio) into the engine's interruption
/// path. No-op until `radio_schedule` rules + voiceover audio exist.
void _attachScheduler(Ref ref, RadioStation station) {
  final scheduler = ref.read(radioSchedulerProvider);
  scheduler.start(station: station.name);
  ref.onDispose(scheduler.stop);
}

/// The programming scheduler (singleton). Exposed so the radio UI can trigger a
/// "Test announcement" (fireNow) and so the session can start/stop it.
final radioSchedulerProvider = Provider<RadioScheduler>((ref) {
  return RadioScheduler(
    client: SupabaseService.isConfigured ? SupabaseService.client : null,
    inject: (seg) => ref
        .read(radioEngineControllerProvider.notifier)
        .requestInterruption(seg),
  );
});
