import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/error/app_exception.dart';
import 'package:explorer_os_mobile/features/music/repositories/music_repository.dart';
import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/providers/radio_engine_providers.dart';
import 'package:explorer_os_mobile/features/radio/repositories/radio_station_repository.dart';
import 'package:explorer_os_mobile/shared/models/radio_station.dart';

/// Bootstraps a listening session: attaches audio output, loads the current
/// station's playlist from the backend (Supabase, via the Music library), and
/// loads it into the engine WITHOUT auto-playing (the UI's Play button starts
/// it, per web autoplay rules).
///
/// This is the glue that finally makes the radio audible: it connects
/// content (Music/Supabase) → engine → audio adapter. Returns the active
/// station for the UI; surfaces a friendly error when the backend isn't
/// configured or has no stations.
final radioSessionProvider = FutureProvider<RadioStation>((ref) async {
  // Attach the audio adapter (engine intent → real sound via just_audio).
  ref.read(radioAudioServiceProvider);

  final stations = await ref.watch(radioStationsProvider.future);
  if (stations.isEmpty) {
    throw const AppException(
      'No radio stations are available yet. Add stations in the backend to '
      'start listening.',
      type: AppExceptionType.notFound,
    );
  }

  final station = stations.first;
  final songs =
      await ref.read(musicRepositoryProvider).songsForStation(station.id);

  ref
      .read(radioEngineServiceProvider)
      .changeStation(station, songs: songs, autoPlay: false);

  // Ensure the controller is alive so it reflects engine events in the UI.
  ref.read(radioEngineControllerProvider);

  return station;
});
