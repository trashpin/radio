import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/services/station_manager.dart';

/// Selects the next music track for the current station.
///
/// WHY THIS EXISTS: music selection is a distinct policy ("what song next?").
/// It delegates to [StationManager], which now drives selection through the
/// Smart Music Rotation Engine (scored, anti-repeat, non-sequential) instead of
/// a playlist cursor — giving a single seam to evolve that policy without
/// touching the engine.
class MusicScheduler {
  const MusicScheduler();

  AudioSegment? next(StationManager station) => station.nextMusicSegment();
}
