import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';

/// The generated (or already-cached) trail audio introduction — a real
/// result from the `forest-trail-audio` Edge Function, never a client-side
/// guess. Null fields mean generation failed; callers must show a real
/// error/retry state, never invent a placeholder.
class TrailAudioResult {
  const TrailAudioResult({
    required this.audioUrl,
    required this.script,
    required this.durationSeconds,
    required this.cached,
  });
  final String audioUrl;
  final String? script;
  final double? durationSeconds;
  final bool cached;
}

/// Client for the `forest-trail-audio` Edge Function (spec: "Trail Audio
/// Tour"). Reuses the SAME ElevenLabs integration copilot-line/
/// forest-discovery already call — this service just invokes it for one
/// more purpose, it is not a second integration.
class ForestTrailAudioService {
  const ForestTrailAudioService();

  Future<TrailAudioResult?> ensureAudio(String trailId) async {
    if (!SupabaseService.isConfigured) return null;
    try {
      final res = await SupabaseService.client.functions.invoke(
        'forest-trail-audio',
        body: {'trailId': trailId},
      ).timeout(const Duration(seconds: 45));
      final data = res.data;
      if (data is Map) {
        final url = (data['audioUrl'] as String?)?.trim();
        if (url != null && url.isNotEmpty) {
          return TrailAudioResult(
            audioUrl: url,
            script: data['script'] as String?,
            durationSeconds: (data['durationSeconds'] as num?)?.toDouble(),
            cached: data['cached'] as bool? ?? false,
          );
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

final forestTrailAudioServiceProvider =
    Provider<ForestTrailAudioService>((ref) => const ForestTrailAudioService());
