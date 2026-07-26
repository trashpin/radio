import 'dart:math';

import 'package:explorer_os_mobile/features/dj/banter/banter_engine.dart';
import 'package:explorer_os_mobile/features/dj/models/dj_clip.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
import 'package:explorer_os_mobile/features/radio_automation/models/radio_schedule_rule.dart';
import 'package:explorer_os_mobile/features/radio_automation/models/radio_segment.dart';
import 'package:explorer_os_mobile/features/radio_automation/services/automation_engine.dart';

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

  /// Pre-generated clips (DJ voice) loaded at session start. When one matches
  /// the station+situation, it plays instead of on-device TTS.
  List<DjClip> _clips = const [];
  void setClips(List<DjClip> clips) => _clips = clips;

  /// Rule-driven automation (radio_schedule_rules + radio_segments). When set,
  /// matching rules decide what plays between songs; otherwise the default
  /// "every N songs" DJ banter applies.
  AutomationEngine? _automation;
  List<RadioScheduleRule> _rules = const [];
  List<RadioSegment> _segments = const [];
  void setAutomation(
    AutomationEngine engine,
    List<RadioScheduleRule> rules,
    List<RadioSegment> segments,
  ) {
    _automation = engine;
    _rules = rules;
    _segments = segments;
  }

  /// Builds a playable segment from a library [RadioSegment] (its own audio if
  /// voiced, else its script via TTS).
  AudioSegment _fromSegment(RadioSegment s) => AudioSegment(
        id: 'auto:${s.id}:${DateTime.now().microsecondsSinceEpoch}',
        title: s.title.isEmpty ? 'On air' : s.title,
        artist: s.voice ?? 'DJ',
        type: AudioSegmentType.announcement,
        priority: PlaybackPriority.scheduledAnnouncement,
        audioUrl: s.hasAudio ? s.audioUrl : null,
        spokenText: s.hasAudio ? null : s.script,
        interruptible: true,
        resumeAfter: false,
      );

  /// Time-based rule evaluation (called on a periodic tick by the session).
  /// Returns a segment to interrupt with, or null.
  AudioSegment? onTick({
    required String? radioStationName,
    required int sessionMinutes,
    DateTime? now,
  }) {
    final engine = _automation;
    if (engine == null || _rules.isEmpty) return null;
    final seg = engine.onTick(_rules, _segments,
        station: stationFor(radioStationName),
        sessionMinutes: sessionMinutes,
        now: now);
    return seg == null ? null : _fromSegment(seg);
  }

  DjClip? _pickClip(DjStation station, BanterSituation situation) {
    final matches = _clips
        .where((c) =>
            c.situation == situation &&
            (c.station == station || c.station == DjStation.all))
        .toList();
    if (matches.isEmpty) return null;
    return matches[_rng.nextInt(matches.length)];
  }

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

  /// After [finishedMusic] plays, maybe return a segment to play between songs.
  AudioSegment? onMusicPlayed(AudioSegment finishedMusic,
      {String? radioStationName}) {
    if (!enabled) return null;
    _count++;

    // 1) Rule-driven automation (radio_schedule_rules) decides first — its own
    // cadence (every-N-songs, after-song, random) governs when it fires.
    final auto = _automation;
    if (auto != null && _rules.isNotEmpty) {
      final seg = auto.onSong(_rules, _segments,
          station: stationFor(radioStationName), songIndex: _count);
      if (seg != null) return _fromSegment(seg);
    }

    // 2) Otherwise, the default DJ banter every N songs.
    if (everyNSongs <= 0 || _count % everyNSongs != 0) return null;

    final station = stationFor(radioStationName);

    // Mostly a song outro/transition; occasionally a station ID for variety.
    final situation = _rng.nextInt(4) == 0
        ? BanterSituation.stationId
        : BanterSituation.songOutro;

    // Prefer a pre-generated clip in the DJ's ElevenLabs voice.
    final clip = _pickClip(station, situation) ??
        _pickClip(station, BanterSituation.stationId);
    if (clip != null) {
      return AudioSegment(
        id: 'dj:clip:${clip.id}:${DateTime.now().microsecondsSinceEpoch}',
        title: 'On air',
        artist: clip.voiceName ?? 'DJ',
        type: AudioSegmentType.announcement,
        priority: PlaybackPriority.scheduledAnnouncement,
        audioUrl: clip.audioUrl,
        interruptible: true,
        resumeAfter: false,
      );
    }

    // Fall back to dynamically-generated, on-device TTS banter.
    final ctx = BanterContext(
      station: brand,
      park: park,
      songTitle: finishedMusic.title.isEmpty ? null : finishedMusic.title,
      artist: finishedMusic.artist,
      timeOfDay: _timeOfDay(),
    );
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
