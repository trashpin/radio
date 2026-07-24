import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/station_id.dart';

/// Produces station identification segments for the current station.
///
/// WHY THIS EXISTS: "You're listening to Explorer Radio" tags are their own
/// concern — a station can have several that cycle. This service holds the
/// current station's [StationID]s and yields the next one; the
/// AnnouncementScheduler/engine decides WHEN to play it.
class StationIdentificationService {
  final List<StationID> _ids = [];
  int _cursor = 0;

  void configure(List<StationID> ids) {
    _ids
      ..clear()
      ..addAll(ids);
    _cursor = 0;
  }

  bool get hasIds => _ids.isNotEmpty;

  /// The next station-ID segment (cycled), or null if none configured.
  AudioSegment? next() {
    if (_ids.isEmpty) return null;
    final id = _ids[_cursor % _ids.length];
    _cursor++;
    return id.toSegment();
  }
}
