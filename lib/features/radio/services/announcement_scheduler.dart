import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';

/// Decides WHEN scheduled announcements and station identifications should play.
///
/// WHY THIS EXISTS: like narrations, announcements and "you're listening to…"
/// station IDs need sensible pacing. This scheduler tracks two independent
/// cadences (announcements are consumed once; station IDs cycle and repeat) and
/// emits at most one due segment per music track. Station identifications take
/// precedence when both are due in the same slot.
class AnnouncementScheduler {
  final List<AudioSegment> _announcements = [];
  final List<AudioSegment> _stationIds = [];
  int _announcementEvery = 4;
  int _stationIdEvery = 5;
  int _announcementSince = 0;
  int _stationIdSince = 0;

  void configure({
    required int announcementEveryTracks,
    required int stationIdEveryTracks,
    required List<AudioSegment> announcements,
    required List<AudioSegment> stationIds,
  }) {
    _announcementEvery =
        announcementEveryTracks < 1 ? 1 : announcementEveryTracks;
    _stationIdEvery = stationIdEveryTracks < 1 ? 1 : stationIdEveryTracks;
    _announcements
      ..clear()
      ..addAll(announcements);
    _stationIds
      ..clear()
      ..addAll(stationIds);
    _announcementSince = 0;
    _stationIdSince = 0;
  }

  /// Call after each music track. Returns a due station ID or announcement, or
  /// null.
  AudioSegment? onMusicPlayed() {
    _announcementSince++;
    _stationIdSince++;

    if (_stationIds.isNotEmpty && _stationIdSince >= _stationIdEvery) {
      _stationIdSince = 0;
      // Cycle station IDs so they repeat over time.
      final id = _stationIds.removeAt(0);
      _stationIds.add(id);
      return id;
    }

    if (_announcements.isNotEmpty && _announcementSince >= _announcementEvery) {
      _announcementSince = 0;
      return _announcements.removeAt(0);
    }

    return null;
  }
}
