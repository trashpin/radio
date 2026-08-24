import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';

/// One generated (or cached) narration result from `discover-narration`.
class MissionNarrationResult {
  const MissionNarrationResult({required this.text, this.audioUrl});
  final String text;
  final String? audioUrl;
  bool get hasAudio => (audioUrl ?? '').trim().isNotEmpty;
}

/// Client for `discover-narration`'s `subjectType: 'mission'` path — the
/// SAME OpenAI+ElevenLabs edge function every other narration surface in
/// this app already calls, extended (not duplicated) for Marion County
/// Adventures. Mission narration text is always admin-authored verbatim
/// script (opening/travel/approach/arrival/old-world beats), so the request
/// always includes [text] and the server speaks it exactly, skipping OpenAI
/// — the same shortcut already built for the Discover greeting.
class MissionNarrationService {
  const MissionNarrationService();

  /// [subjectId] must be globally unique per distinct line — callers use the
  /// content row's own id (a mission_travel_stories/old_worlds id, or the
  /// mission's own id for the opening line) so the cache in
  /// `discover_narrations` never collides across missions/stops.
  Future<MissionNarrationResult?> requestFor({
    required String subjectId,
    required String kind,
    required String text,
  }) async {
    if (!SupabaseService.isConfigured || text.trim().isEmpty) return null;
    try {
      final res = await SupabaseService.client.functions.invoke(
        'discover-narration',
        body: {
          'subjectType': 'mission',
          'subjectId': subjectId,
          'kind': kind,
          'text': text,
        },
      ).timeout(const Duration(seconds: 45));
      final data = res.data;
      if (data is Map) {
        final t = (data['text'] as String?)?.trim();
        if (t != null && t.isNotEmpty) {
          return MissionNarrationResult(text: t, audioUrl: data['audioUrl'] as String?);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

final missionNarrationServiceProvider =
    Provider<MissionNarrationService>((ref) => const MissionNarrationService());
