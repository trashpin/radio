import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';

/// Runtime "what plays when" engine.
///
/// Reads active rules from `radio_schedule` plus the pool of playable
/// announcements (`safety_messages` / `wildlife_alerts` that have an
/// `audio_url`), and — on a periodic tick — injects the highest-priority *due*
/// announcement into the radio via [inject] (which routes to the engine's
/// interruption path, ducking music and resuming after). Rules with no playable
/// content are skipped, so it's a safe no-op until voiceovers are uploaded.
class RadioScheduler {
  RadioScheduler({required this.client, required this.inject});

  /// Null when Supabase isn't configured (e.g. preview) — scheduler no-ops.
  final SupabaseClient? client;
  final void Function(AudioSegment segment) inject;

  Timer? _timer;
  bool _loaded = false;
  final Map<String, DateTime> _lastFired = {};
  List<Map<String, dynamic>> _rules = const [];
  List<Map<String, dynamic>> _safety = const [];
  List<Map<String, dynamic>> _wildlife = const [];
  List<Map<String, dynamic>> _stories = const [];
  int _safetyIdx = 0;
  int _wildlifeIdx = 0;
  int _storyIdx = 0;

  Future<void> start({String? station, String? parkCode}) async {
    await reload(station: station, parkCode: parkCode);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
  }

  Future<List<Map<String, dynamic>>> _tryLoad(String table,
      {bool nullAudio = false}) async {
    if (client == null) return const [];
    try {
      var q = client!.from(table).select().eq('active', true);
      if (nullAudio) q = q.not('audio_url', 'is', null);
      return ((await q) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return const [];
    }
  }

  Future<void> reload({String? station, String? parkCode}) async {
    if (client == null) return;
    _rules = await _tryLoad('radio_schedule');
    _safety = await _tryLoad('safety_messages', nullAudio: true);
    _wildlife = await _tryLoad('wildlife_alerts', nullAudio: true);
    // stories: published + has audio_url (column added in migration 0013).
    try {
      _stories = ((await client!
              .from('stories')
              .select()
              .eq('published', true)
              .not('audio_url', 'is', null)) as List)
          .cast<Map<String, dynamic>>();
    } catch (_) {
      _stories = const [];
    }
    _loaded = true;
  }

  /// Immediately inject the next available announcement (for a "Test now"
  /// button) — ignores cadence. Loads content on first use.
  Future<void> fireNow() async {
    if (!_loaded) await reload();
    final seg = _segmentFor('safety') ??
        _segmentFor('wildlife') ??
        _segmentFor('story');
    if (seg != null) inject(seg);
  }

  void _tick() {
    if (_rules.isEmpty) return;
    final now = DateTime.now();
    final interval = _rules
        .where((r) => (r['cadence'] ?? 'interval') == 'interval')
        .toList()
      ..sort((a, b) =>
          ((b['priority'] ?? 0) as int).compareTo((a['priority'] ?? 0) as int));
    for (final r in interval) {
      final id = r['id'].toString();
      final mins = (r['interval_minutes'] ?? 15) as int;
      final last = _lastFired[id];
      if (last != null && now.difference(last).inMinutes < mins) continue;
      final seg = _segmentFor((r['content_type'] ?? 'safety') as String);
      if (seg == null) continue;
      _lastFired[id] = now;
      inject(seg);
      return; // at most one announcement per tick
    }
  }

  AudioSegment? _segmentFor(String type) {
    switch (type) {
      case 'safety':
        if (_safety.isEmpty) return null;
        final m = _safety[_safetyIdx++ % _safety.length];
        return AudioSegment(
          id: 'safety:${m['id']}',
          title: (m['title'] ?? 'Safety message') as String,
          type: AudioSegmentType.safetyWarning,
          priority: PlaybackPriority.safetyWarning,
          audioUrl: m['audio_url'] as String?,
          interruptible: false,
          resumeAfter: true,
        );
      case 'wildlife':
        if (_wildlife.isEmpty) return null;
        final m = _wildlife[_wildlifeIdx++ % _wildlife.length];
        return AudioSegment(
          id: 'wildlife:${m['id']}',
          title: (m['title'] ?? 'Wildlife update') as String,
          type: AudioSegmentType.wildlifeAlert,
          priority: PlaybackPriority.scheduledAnnouncement,
          audioUrl: m['audio_url'] as String?,
          interruptible: false,
          resumeAfter: true,
        );
      case 'story':
        if (_stories.isEmpty) return null;
        final m = _stories[_storyIdx++ % _stories.length];
        return AudioSegment(
          id: 'story:${m['story_id'] ?? m['id']}',
          title: (m['title'] ?? 'Story') as String,
          type: AudioSegmentType.narration,
          priority: PlaybackPriority.scheduledAnnouncement,
          audioUrl: m['audio_url'] as String?,
          interruptible: true,
          resumeAfter: true,
        );
      default:
        return null;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
