import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/what_is_that/models/what_is_that_topic.dart';

/// Data access for "What Is That?"'s topic narrations (`what_is_that_narrations`,
/// generated server-side by the narration worker's `doWhatIsThatTopic` —
/// see supabase/functions/narration-worker/worker.ts). Mirrors the exact
/// enqueue-then-trigger-then-poll pattern already proven by
/// `RadioAutomationRepository`/`NearbyGemsRepository`/`DjBanterRepository`.
class WhatIsThatNarrationRepository {
  const WhatIsThatNarrationRepository();

  /// Reads back a cached, already-voiced narration for (locationId, topic),
  /// or null if it hasn't been generated (or voiced) yet.
  Future<WhatIsThatNarration?> narrationFor(
    String locationId,
    WhatIsThatTopic topic,
  ) async {
    if (!SupabaseService.isConfigured) return null;
    try {
      final row = await SupabaseService.client
          .from('what_is_that_narrations')
          .select('script, audio_url, voice_id')
          .eq('location_id', locationId)
          .eq('topic', topic.id)
          .maybeSingle();
      if (row == null) return null;
      final audio = (row['audio_url'] as String?)?.trim();
      if (audio == null || audio.isEmpty) return null; // queued but not voiced yet
      return WhatIsThatNarration.fromJson(row);
    } catch (_) {
      return null;
    }
  }

  /// Enqueues generation for (locationId, topic), drained by the existing
  /// narration worker (Google Places supplement + OpenAI script + ElevenLabs
  /// voicing — same DJ Sunny voice every other narration type uses).
  Future<bool> enqueueTopic(String locationId, WhatIsThatTopic topic) async {
    if (!SupabaseService.isConfigured) return false;
    try {
      await SupabaseService.client.from('generation_jobs').insert({
        'destination': 'what_is_that:$locationId:${topic.id}',
        'job_type': 'audio',
        'status': 'pending',
        'progress': 0,
        'notes': 'what_is_that:topic;location_id=$locationId;topic=${topic.id}',
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Asks the narration worker to drain the queue NOW instead of waiting for
  /// the scheduled ~5-minute cron tick. Works only if the `narration-worker`
  /// Edge Function is deployed; returns false otherwise (the scheduled
  /// GitHub worker still processes the job).
  Future<bool> triggerNarrationWorker() async {
    if (!SupabaseService.isConfigured) return false;
    try {
      await SupabaseService.client.functions.invoke('narration-worker');
      return true;
    } catch (_) {
      return false;
    }
  }
}

final whatIsThatNarrationRepositoryProvider =
    Provider<WhatIsThatNarrationRepository>(
        (ref) => const WhatIsThatNarrationRepository());
