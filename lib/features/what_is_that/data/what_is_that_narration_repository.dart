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

  /// Cheap, instant read of already-cached Google Places photos for several
  /// candidates at once (one bulk query against our own cache table — never
  /// calls the Places API itself). Used to help identify multiple candidates
  /// with a photo when one is already on hand; a candidate with no row here
  /// simply has no cached photo yet, not an error.
  Future<Map<String, String?>> cachedPhotosFor(List<String> locationIds) async {
    if (!SupabaseService.isConfigured || locationIds.isEmpty) return const {};
    try {
      final rows = await SupabaseService.client
          .from('what_is_that_place_data')
          .select('location_id, photo_url')
          .inFilter('location_id', locationIds) as List;
      return {
        for (final r in rows.cast<Map<String, dynamic>>())
          (r['location_id'] as String): r['photo_url'] as String?,
      };
    } catch (_) {
      return const {};
    }
  }

  /// Opportunistically asks the worker to cache a Google Places photo for
  /// [locationId] — spec: "photo request only as a LAST resort," so this is
  /// deliberately fire-and-forget: no polling, no waiting, and it never
  /// blocks the candidate list from showing (with or without a photo) right
  /// away. Only worth calling for a candidate that has neither our own
  /// database image nor an already-cached Places photo.
  Future<void> enqueuePhotoOnly(String locationId) async {
    if (!SupabaseService.isConfigured) return;
    try {
      await SupabaseService.client.from('generation_jobs').insert({
        'destination': 'what_is_that:$locationId:photo',
        'job_type': 'audio',
        'status': 'pending',
        'progress': 0,
        'notes': 'what_is_that:photo;location_id=$locationId',
      });
      await triggerNarrationWorker();
    } catch (_) {
      // Best-effort only — a missing photo is never a failure for this screen.
    }
  }
}

final whatIsThatNarrationRepositoryProvider =
    Provider<WhatIsThatNarrationRepository>(
        (ref) => const WhatIsThatNarrationRepository());
