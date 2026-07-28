import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';

/// Per-experience playback history used to prevent duplicate/annoying triggers.
class PlayRecord {
  PlayRecord({
    this.timesPlayed = 0,
    this.lastPlayedAt,
    this.lastLatitude,
    this.lastLongitude,
    this.playedThisVisit = 0,
  });

  int timesPlayed;
  DateTime? lastPlayedAt;
  double? lastLatitude;
  double? lastLongitude;
  int playedThisVisit;
}

/// Tracks what narration has already played, when, and where — so the system
/// never replays a narration inappropriately.
///
/// This is pure bookkeeping: it makes NO audio decisions itself and holds no
/// audio. The Around Me layer / Playback Manager consult [shouldTrigger] before
/// auto-playing a POI narration, and call [markPlayed] afterwards.
class AntiRepeatTracker {
  AntiRepeatTracker({
    this.minInterval = const Duration(minutes: 10),
    this.minDistanceMeters = 150,
    this.maxPerVisit = 2,
  });

  /// Minimum time before the same experience may auto-trigger again.
  final Duration minInterval;

  /// Minimum distance the visitor must travel away-and-back before a re-trigger.
  final double minDistanceMeters;

  /// Cap on auto-triggers for one experience within a single visit.
  final int maxPerVisit;

  final Map<String, PlayRecord> _records = {};

  /// Begins a new visit (e.g. app opened, or a new park entered): per-visit
  /// counters reset while lifetime history is preserved.
  void startNewVisit() {
    for (final r in _records.values) {
      r.playedThisVisit = 0;
    }
  }

  PlayRecord? recordFor(String id) => _records[id];

  int timesPlayed(String id) => _records[id]?.timesPlayed ?? 0;

  DateTime? lastPlayed(String id) => _records[id]?.lastPlayedAt;

  bool hasPlayed(String id) => (_records[id]?.timesPlayed ?? 0) > 0;

  /// Distance (meters) the visitor has moved since this experience last played,
  /// or `double.infinity` if it never played / has no recorded position.
  double distanceSinceLastPlayed(String id, double lat, double lng) {
    final r = _records[id];
    if (r?.lastLatitude == null || r?.lastLongitude == null) {
      return double.infinity;
    }
    return GeoMath.distanceMeters(r!.lastLatitude!, r.lastLongitude!, lat, lng);
  }

  /// Whether [id]'s narration may auto-trigger now, given elapsed time and
  /// distance moved since it last played and the per-visit cap.
  bool shouldTrigger(
    String id, {
    required DateTime now,
    required double latitude,
    required double longitude,
  }) {
    final r = _records[id];
    if (r == null || r.timesPlayed == 0) return true;
    if (r.playedThisVisit >= maxPerVisit) return false;
    final elapsedOk = r.lastPlayedAt == null ||
        now.difference(r.lastPlayedAt!) >= minInterval;
    final movedOk =
        distanceSinceLastPlayed(id, latitude, longitude) >= minDistanceMeters;
    return elapsedOk || movedOk;
  }

  /// Records that [id]'s narration played now, at the given position.
  void markPlayed(
    String id, {
    required DateTime now,
    required double latitude,
    required double longitude,
  }) {
    final r = _records.putIfAbsent(id, PlayRecord.new);
    r.timesPlayed += 1;
    r.playedThisVisit += 1;
    r.lastPlayedAt = now;
    r.lastLatitude = latitude;
    r.lastLongitude = longitude;
  }

  void reset() => _records.clear();
}
