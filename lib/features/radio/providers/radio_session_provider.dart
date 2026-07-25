import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/error/app_exception.dart';
import 'package:explorer_os_mobile/features/destinations/data/destination_repository.dart';
import 'package:explorer_os_mobile/features/media/data/media_repository.dart';
import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/providers/radio_engine_providers.dart';
import 'package:explorer_os_mobile/features/radio/providers/stations_provider.dart';
import 'package:explorer_os_mobile/shared/models/radio_station.dart';
import 'package:explorer_os_mobile/shared/models/song.dart';

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

  final media = ref.read(mediaRepositoryProvider);

  // If the user picked a station from the Stations screen, honor it; load its
  // audio from the linked destination's media (empty for curated stations
  // until they have content).
  final selected = ref.watch(selectedStationProvider);
  if (selected != null) {
    final songs = selected.destinationId != null
        ? await media.songsForDestination(selected.destinationId!)
        : const <Song>[];
    ref
        .read(radioEngineServiceProvider)
        .changeStation(selected, songs: songs, autoPlay: false);
    ref.read(radioEngineControllerProvider);
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
  final songs = await media.songsForDestination(destination.id);

  ref
      .read(radioEngineServiceProvider)
      .changeStation(station, songs: songs, autoPlay: false);

  // Ensure the controller is alive so it reflects engine events in the UI.
  ref.read(radioEngineControllerProvider);

  return station;
});
