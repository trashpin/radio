import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/radio/banter/banter_engine.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';

/// A resolved, playable banter clip — reused from a location's existing content
/// (recorded audio, else its AI narration script / description as TTS).
class BanterClip {
  const BanterClip({this.audioUrl, this.text = ''});
  final String? audioUrl;
  final String text;
  bool get hasAudio => audioUrl != null && audioUrl!.trim().isNotEmpty;
  bool get isEmpty => !hasAudio && text.trim().isEmpty;
}

/// Live inputs the scheduler needs, supplied by the session layer (so this
/// stays a pure service): the user's position, current county, all master
/// locations, and a resolver that turns a location into its playable clip
/// (reusing the AI narration/audio it already carries).
class BanterRuntime {
  const BanterRuntime({
    required this.lat,
    required this.lng,
    required this.county,
    required this.locations,
    required this.resolve,
  });
  final double lat;
  final double lng;
  final String? county;
  final List<MasterLocation> locations;
  final BanterClip Function(MasterLocation) resolve;
}

typedef BanterContextProvider = BanterRuntime? Function();

/// Between-song scheduler that mixes LOCAL banter (from the master locations
/// around the user) into the radio, using [BanterEngine] for the park→city→
/// county priority + cooldown, and reusing each location's existing content for
/// the actual clip. Plugs into `RadioEngineService._injectScheduledContent`
/// exactly like the DJ banter scheduler.
class LocationBanterScheduler {
  LocationBanterScheduler({
    this.everyNSongs = 3,
    BanterEngine engine = const BanterEngine(),
  }) : _engine = engine;

  /// Master switch (off = never inserts banter).
  bool enabled = true;

  /// Insert local banter roughly once every N songs (paces it so it feels
  /// natural rather than after every track).
  final int everyNSongs;

  BanterEngine _engine;
  int _count = 0;

  /// clip id → when it last played (drives the cooldown across the session).
  final Map<String, DateTime> _lastPlayed = {};

  BanterContextProvider? _context;

  /// Wires the live location/position source (called once from the session).
  void configure({required BanterContextProvider context, BanterEngine? engine}) {
    _context = context;
    if (engine != null) _engine = engine;
  }

  /// Called after each music track. Returns a banter segment to play next, or
  /// null to leave the gap for music/other content.
  AudioSegment? onMusicPlayed() {
    if (!enabled) return null;
    final ctx = _context?.call();
    if (ctx == null) return null; // no GPS/locations yet
    _count++;
    if (everyNSongs <= 0 || _count % everyNSongs != 0) return null;

    final now = DateTime.now();
    final pick = _engine.selectNext(
      ctx.lat,
      ctx.lng,
      ctx.locations,
      now: now,
      lastPlayed: _lastPlayed,
      county: ctx.county,
    );
    if (pick == null) return null; // everything eligible is cooling down

    final clip = ctx.resolve(pick.location);
    if (clip.isEmpty) return null;
    _lastPlayed[pick.location.id] = now;

    return AudioSegment(
      id: 'banter:${pick.scope.name}:${pick.location.id}:'
          '${now.microsecondsSinceEpoch}',
      title: pick.location.name,
      artist: 'Local',
      type: AudioSegmentType.narration,
      priority: PlaybackPriority.scheduledAnnouncement,
      audioUrl: clip.hasAudio ? clip.audioUrl : null,
      spokenText: clip.hasAudio ? null : clip.text,
      interruptible: true,
      resumeAfter: false,
    );
  }

  void reset() => _count = 0;
}
