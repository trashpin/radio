import 'dart:math';

import 'package:explorer_os_mobile/features/dj/banter/banter_engine.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';

/// Decides when the DJ talks between songs and produces the spoken banter.
///
/// Called by the engine after each music track finishes. It stays quiet most of
/// the time (the DJ doesn't talk constantly) — roughly every [everyNSongs]
/// tracks it generates a short, context-aware line (song outro / transition)
/// from the [BanterEngine], returned as a spoken [AudioSegment] the audio
/// adapter voices via TTS.
class DjBanterScheduler {
  DjBanterScheduler({
    BanterEngine? engine,
    this.everyNSongs = 2,
    this.enabled = true,
    this.brand = 'Ocala National Forest Radio',
    this.park = 'Ocala National Forest',
    Random? rng,
  })  : _engine = engine ?? BanterEngine(),
        _rng = rng ?? Random();

  final BanterEngine _engine;
  final int everyNSongs;
  bool enabled;
  final String brand;
  final String park;
  final Random _rng;

  int _count = 0;

  /// Maps a radio station name to a DJ station flavor for template selection.
  static DjStation stationFor(String? name) {
    final n = (name ?? '').toLowerCase();
    if (n.contains('country')) return DjStation.country;
    if (n.contains('rock')) return DjStation.rock;
    if (n.contains('top') || n.contains('hit')) return DjStation.topHits;
    if (n.contains('kid')) return DjStation.kids;
    return DjStation.all;
  }

  static String _timeOfDay() {
    final h = DateTime.now().hour;
    if (h < 12) return 'morning';
    if (h < 17) return 'afternoon';
    return 'evening';
  }

  /// After [finishedMusic] plays, maybe return a spoken banter segment.
  AudioSegment? onMusicPlayed(AudioSegment finishedMusic,
      {String? radioStationName}) {
    if (!enabled || everyNSongs <= 0) return null;
    _count++;
    if (_count % everyNSongs != 0) return null;

    final station = stationFor(radioStationName);
    final ctx = BanterContext(
      station: brand,
      park: park,
      songTitle: finishedMusic.title.isEmpty ? null : finishedMusic.title,
      artist: finishedMusic.artist,
      timeOfDay: _timeOfDay(),
    );

    // Mostly a song outro/transition; occasionally a station ID for variety.
    final situation = _rng.nextInt(4) == 0
        ? BanterSituation.stationId
        : BanterSituation.songOutro;
    final text = _engine.generate(station, situation, ctx) ??
        _engine.generate(DjStation.all, BanterSituation.stationId, ctx);
    if (text == null || text.trim().isEmpty) return null;

    return AudioSegment(
      id: 'dj:${DateTime.now().microsecondsSinceEpoch}',
      title: 'On air',
      artist: 'DJ',
      type: AudioSegmentType.announcement,
      priority: PlaybackPriority.scheduledAnnouncement,
      spokenText: text,
      interruptible: true,
      resumeAfter: false,
    );
  }

  void reset() => _count = 0;
}
