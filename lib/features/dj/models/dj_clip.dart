import 'package:explorer_os_mobile/features/dj/banter/banter_engine.dart';

/// A pre-generated DJ banter clip: a line of banter rendered to audio in a
/// specific DJ's ElevenLabs voice and stored in Supabase. The runtime prefers
/// these (so the on-air voice matches the DJ personality) and falls back to
/// on-device TTS when no matching clip exists.
class DjClip {
  const DjClip({
    required this.id,
    required this.station,
    required this.situation,
    required this.audioUrl,
    this.djId,
    this.voiceId,
    this.voiceName,
    this.text,
  });

  final String id;
  final DjStation station;
  final BanterSituation situation;
  final String audioUrl;
  final String? djId;
  final String? voiceId;
  final String? voiceName;
  final String? text;

  static DjStation _station(String? s) => DjStation.values.firstWhere(
        (e) => e.name == s,
        orElse: () => DjStation.all,
      );

  static BanterSituation? _situation(String? s) {
    for (final e in BanterSituation.values) {
      if (e.name == s) return e;
    }
    return null;
  }

  /// Parses a `dj_banter_clips` row; returns null if it has no usable audio or
  /// an unknown situation.
  static DjClip? fromJson(Map<String, dynamic> j) {
    final url = (j['audio_url'] ?? '') as String;
    final situation = _situation(j['situation'] as String?);
    if (url.isEmpty || situation == null) return null;
    return DjClip(
      id: (j['id'] ?? j['clip_id'] ?? url).toString(),
      station: _station(j['station'] as String?),
      situation: situation,
      audioUrl: url,
      djId: j['dj_id'] as String?,
      voiceId: j['voice_id'] as String?,
      voiceName: j['voice_name'] as String?,
      text: j['text'] as String?,
    );
  }
}
