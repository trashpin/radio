import 'dart:math';

import 'package:explorer_os_mobile/features/dj/banter/banter_engine.dart';
import 'package:explorer_os_mobile/features/dj/banter_studio/banter_category.dart';
import 'package:explorer_os_mobile/features/dj/banter_studio/dj_banter_clip.dart';
import 'package:explorer_os_mobile/features/dj/banter_studio/gps_banter_director.dart';
import 'package:explorer_os_mobile/features/dj/models/dj_clip.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/geo_point.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
import 'package:explorer_os_mobile/features/radio/models/tell_me_more_context.dart';
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

  // ── GPS-Aware DJ Banter Studio integration ────────────────────────────────
  // When a per-destination banter library is loaded, the DJ speaks those
  // GPS-aware, conversational lines between songs (in the DJ's voice, or via TTS
  // for unvoiced clips) — taking precedence over the generic template banter.

  GpsBanterDirector? _gpsDirector;
  BanterTrip _banterTrip = BanterTrip();
  List<DjBanterClip> _banterLibrary = const [];
  GpsBanterContext Function()? _banterContext;
  void Function(String clipId)? _onBanterPlayed;

  // ── County knowledge (from CountyConfig.facts) ────────────────────────────
  // Admin-authored local facts for the current county. When present, the DJ
  // occasionally drops one between songs — genuine, editable "local knowledge"
  // reusing the County Manager content, not a separate store.
  String? _county;
  List<String> _countyFacts = const [];
  int _factRotation = 0;

  /// Sets the current county's name + its fact pool (call on county change).
  void setCountyFacts({String? county, List<String> facts = const []}) {
    _county = county;
    _countyFacts = [for (final f in facts) if (f.trim().isNotEmpty) f.trim()];
  }

  /// Priority of categories to consider between songs (context-relevant teases
  /// first, then general transitions).
  static const List<BanterCategory> _banterPriority = [
    BanterCategory.wildlifeTease,
    BanterCategory.historyTease,
    BanterCategory.geologyTease,
    BanterCategory.plantTease,
    BanterCategory.birdTease,
    BanterCategory.hiddenGem,
    BanterCategory.scenicObservation,
    BanterCategory.interestingFact,
    BanterCategory.photoOpportunity,
    BanterCategory.trailSuggestion,
    BanterCategory.songOutro,
    BanterCategory.promotion,
    BanterCategory.stationId,
  ];

  /// Wires the GPS banter director + a live-context supplier + play callback.
  void setGpsBanter({
    required GpsBanterDirector director,
    required BanterTrip trip,
    required GpsBanterContext Function() context,
    void Function(String clipId)? onPlayed,
  }) {
    _gpsDirector = director;
    _banterTrip = trip;
    _banterContext = context;
    _onBanterPlayed = onPlayed;
  }

  /// Refreshes the published banter library (called as the destination changes).
  void setBanterLibrary(List<DjBanterClip> library) =>
      _banterLibrary = library;

  bool get hasGpsBanter =>
      _gpsDirector != null && _banterContext != null && _banterLibrary.isNotEmpty;

  /// Picks a GPS-aware library clip for the current moment, or null.
  AudioSegment? _gpsBanter() {
    final director = _gpsDirector;
    final ctxFn = _banterContext;
    if (director == null || ctxFn == null || _banterLibrary.isEmpty) return null;
    final ctx = ctxFn();
    final sel = director.pickAny(_banterLibrary, _banterPriority, ctx, _banterTrip);
    if (sel == null) return null;
    _onBanterPlayed?.call(sel.clip.id);
    final hasAudio = sel.clip.hasAudio;
    return AudioSegment(
      id: 'djgps:${sel.clip.id}:${DateTime.now().microsecondsSinceEpoch}',
      title: 'On air',
      artist: sel.clip.voiceName ?? 'DJ',
      type: AudioSegmentType.announcement,
      priority: PlaybackPriority.scheduledAnnouncement,
      audioUrl: hasAudio ? sel.clip.audioUrl : null,
      spokenText: hasAudio ? null : sel.text,
      interruptible: true,
      resumeAfter: false,
      tellMeMoreContext: TellMeMoreContext(
        subject: ctx.upcomingAttraction ?? ctx.park ?? ctx.county,
        locationId: null,
        destinationId: sel.clip.destinationId,
        destinationCode: sel.clip.destinationCode,
        category: sel.clip.category.id,
        banterText: sel.text,
        knowledgeContentId: sel.clip.id,
        location: (ctx.latitude != null && ctx.longitude != null)
            ? GeoPoint(latitude: ctx.latitude!, longitude: ctx.longitude!)
            : null,
      ),
    );
  }

  /// ~1-in-3 of the time (when facts are loaded), returns a spoken county-fact
  /// segment built from the next rotating [CountyConfig.facts] entry; else null.
  AudioSegment? _maybeCountyFact() {
    if (_countyFacts.isEmpty) return null;
    if (_rng.nextInt(3) != 0) return null;
    final fact = _countyFacts[_factRotation.abs() % _countyFacts.length];
    _factRotation++;
    final ctx = BanterContext(
      station: brand,
      park: park,
      county: _county,
      fact: fact,
    );
    final text = _engine.generate(DjStation.all, BanterSituation.countyFact, ctx);
    if (text == null || text.trim().isEmpty) return null;
    return AudioSegment(
      id: 'djcounty:${DateTime.now().microsecondsSinceEpoch}',
      title: 'On air',
      artist: 'DJ',
      type: AudioSegmentType.announcement,
      priority: PlaybackPriority.scheduledAnnouncement,
      spokenText: text,
      interruptible: true,
      resumeAfter: false,
    );
  }

  /// Builds a playable segment from a library [RadioSegment] (its own audio if
  /// voiced, else its script via TTS).
  ///
  /// Semantics are category-aware so the unified announcement content (safety /
  /// wildlife / story now flow through here) keeps its original behavior from
  /// the legacy RadioScheduler: safety can't be interrupted and always resumes
  /// music; wildlife/story duck + resume; ordinary DJ banter plays in the gap
  /// between songs (no resume).
  AudioSegment _fromSegment(RadioSegment s) {
    final (
      AudioSegmentType type,
      PlaybackPriority priority,
      bool interruptible,
      bool resumeAfter,
    ) = switch (s.category) {
      SegmentCategory.safety => (
          AudioSegmentType.safetyWarning,
          PlaybackPriority.safetyWarning,
          false,
          true,
        ),
      SegmentCategory.wildlifeIntro => (
          AudioSegmentType.wildlifeAlert,
          PlaybackPriority.scheduledAnnouncement,
          false,
          true,
        ),
      SegmentCategory.story => (
          AudioSegmentType.narration,
          PlaybackPriority.scheduledAnnouncement,
          true,
          true,
        ),
      _ => (
          AudioSegmentType.announcement,
          PlaybackPriority.scheduledAnnouncement,
          true,
          false,
        ),
    };
    return AudioSegment(
      id: 'auto:${s.id}:${DateTime.now().microsecondsSinceEpoch}',
      title: s.title.isEmpty ? 'On air' : s.title,
      artist: s.voice ?? 'DJ',
      type: type,
      priority: priority,
      audioUrl: s.hasAudio ? s.audioUrl : null,
      spokenText: s.hasAudio ? null : s.script,
      interruptible: interruptible,
      resumeAfter: resumeAfter,
    );
  }

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

    // 3) Prefer the GPS-aware, per-destination banter library when loaded, so
    // the DJ references the actual surroundings and never repeats in a trip.
    final gps = _gpsBanter();
    if (gps != null) return gps;

    // 3b) Occasionally share an admin-authored county fact (CountyConfig.facts)
    // — real, editable local knowledge, rotated so it never repeats too soon.
    final countyFact = _maybeCountyFact();
    if (countyFact != null) return countyFact;

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
