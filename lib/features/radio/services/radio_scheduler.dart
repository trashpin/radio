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

  final SupabaseClient client;
  final void Function(AudioSegment segment) inject;

  Timer? _timer;
  final Map<String, DateTime> _lastFired = {};
  List<Map<String, dynamic>> _rules = const [];
  List<Map<String, dynamic>> _safety = const [];
  List<Map<String, dynamic>> _wildlife = const [];
  int _safetyIdx = 0;
  int _wildlifeIdx = 0;

  Future<void> start({String? station, String? parkCode}) async {
    await reload(station: station, parkCode: parkCode);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
  }

  Future<void> reload({String? station, String? parkCode}) async {
    try {
      _rules = ((await client
              .from('radio_schedule')
              .select()
              .eq('active', true)) as List)
          .cast<Map<String, dynamic>>();
      _safety = ((await client
              .from('safety_messages')
              .select()
              .eq('active', true)
              .not('audio_url', 'is', null)) as List)
          .cast<Map<String, dynamic>>();
      _wildlife = ((await client
              .from('wildlife_alerts')
              .select()
              .eq('active', true)
              .not('audio_url', 'is', null)) as List)
          .cast<Map<String, dynamic>>();
    } catch (_) {
      // Tables/policies not present yet — scheduler stays idle.
      _rules = const [];
      _safety = const [];
      _wildlife = const [];
    }
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
      default:
        return null;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
