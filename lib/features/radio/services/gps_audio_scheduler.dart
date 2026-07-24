import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/geo_point.dart';
import 'package:explorer_os_mobile/features/radio/models/gps_audio_trigger.dart';

/// PREPARES the engine for location-aware audio — intentionally NOT implemented.
///
/// WHY THIS EXISTS (now): to establish the seam so GPS can be added later
/// without touching the engine. It can load [GPSAudioTrigger]s and exposes an
/// [evaluate] hook the engine could poll with the listener's position. Today
/// [evaluate] always returns null (no positioning), so the engine behaves
/// exactly as if GPS were absent.
///
/// FUTURE: [evaluate] will find an armed trigger whose geofence contains
/// [position], mark it fired (respecting `oneShot`), and return a
/// `gpsNarration`-priority [AudioSegment] for the engine to interrupt with.
class GPSAudioScheduler {
  final List<GPSAudioTrigger> _triggers = [];
  final Set<String> _fired = {};

  int get triggerCount => _triggers.length;

  void loadTriggers(List<GPSAudioTrigger> triggers) {
    _triggers
      ..clear()
      ..addAll(triggers);
    _fired.clear();
  }

  /// Location evaluation is not implemented yet — always returns null,
  /// regardless of [position], until the GPS feature is built.
  AudioSegment? evaluate(GeoPoint? position) {
    return null;
  }
}
