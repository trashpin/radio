import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/services/station_manager.dart';

/// Selects the next music track for the current station.
///
/// WHY THIS EXISTS: music selection is a distinct policy ("what song next?")
/// that will grow (shuffle, mood/daypart weighting, avoid-recent, local-artist
/// bias). Today it delegates to [StationManager]'s playlist cursor, giving a
/// single seam to evolve that policy without touching the engine.
class MusicScheduler {
  const MusicScheduler();

  AudioSegment? next(StationManager station) => station.nextMusicSegment();
}
