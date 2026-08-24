import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';

/// One HeyGen avatar-video status check result.
class HeyGenStatusResult {
  const HeyGenStatusResult({required this.status, this.videoUrl, this.error});
  final String status; // processing | completed | failed
  final String? videoUrl;
  final String? error;

  bool get isProcessing => status == 'processing';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
}

/// Client for the `heygen-avatar` edge function — the ONLY place the
/// HeyGen API is ever called from. The API key lives solely in that
/// function's server-side environment; nothing here (or anywhere in the
/// Flutter app) ever sees it. See that function's own doc comment for why
/// generation is a submit-then-poll flow rather than one blocking call.
class HeyGenAvatarService {
  const HeyGenAvatarService();

  /// Starts a render job for [stepId]. [audioUrl] must be this step's
  /// already-generated ElevenLabs narration (see `_generateVoice` in the
  /// Story Builder) — HeyGen lip-syncs the avatar to that exact audio track
  /// rather than re-speaking the script with one of its own, unrelated
  /// voice IDs, so a character sounds identical in audio-only and avatar
  /// scenes. Returns true if the job was successfully submitted (poll
  /// [checkStatus] afterward) — false on any failure (missing key, bad
  /// avatar id, HeyGen error), with [onError] receiving a human-readable
  /// reason.
  Future<bool> generate({
    required String stepId,
    required String avatarId,
    required String avatarType,
    required String audioUrl,
    void Function(String message)? onError,
  }) async {
    if (!SupabaseService.isConfigured) return false;
    try {
      final res = await SupabaseService.client.functions.invoke(
        'heygen-avatar',
        body: {
          'action': 'generate',
          'stepId': stepId,
          'avatarId': avatarId,
          'avatarType': avatarType,
          'audioUrl': audioUrl,
        },
      ).timeout(const Duration(seconds: 30));
      final data = res.data;
      if (data is Map && data['error'] != null) {
        onError?.call(data['error'].toString());
        return false;
      }
      return true;
    } catch (e) {
      onError?.call('$e');
      return false;
    }
  }

  Future<HeyGenStatusResult> checkStatus(String stepId) async {
    if (!SupabaseService.isConfigured) {
      return const HeyGenStatusResult(status: 'failed', error: 'Not configured');
    }
    try {
      final res = await SupabaseService.client.functions.invoke(
        'heygen-avatar',
        body: {'action': 'status', 'stepId': stepId},
      ).timeout(const Duration(seconds: 30));
      final data = res.data;
      if (data is Map) {
        if (data['error'] != null) {
          return HeyGenStatusResult(status: 'failed', error: data['error'].toString());
        }
        return HeyGenStatusResult(
          status: (data['status'] as String?) ?? 'processing',
          videoUrl: data['videoUrl'] as String?,
          error: data['error'] as String?,
        );
      }
      return const HeyGenStatusResult(status: 'failed', error: 'Unexpected response');
    } catch (e) {
      return HeyGenStatusResult(status: 'failed', error: '$e');
    }
  }
}

final heyGenAvatarServiceProvider = Provider<HeyGenAvatarService>((ref) => const HeyGenAvatarService());
