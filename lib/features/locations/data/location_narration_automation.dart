import 'dart:async';

import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

/// Stages of the automated "generate narration on save" flow — surfaced to
/// the admin UI so progress is never a silent spinner.
enum NarrationAutomationStage {
  skipped, // already had audio — nothing to do
  enqueuing,
  generating,
  done,
  failed,
}

/// One progress update from [LocationNarrationAutomation.run]. [message] is
/// always meant to be shown to the admin as-is — no separate "translate this
/// error" step needed.
class NarrationAutomationResult {
  const NarrationAutomationResult(this.stage, this.message);
  final NarrationAutomationStage stage;
  final String message;

  bool get isTerminal =>
      stage == NarrationAutomationStage.skipped ||
      stage == NarrationAutomationStage.done ||
      stage == NarrationAutomationStage.failed;
  bool get isSuccess =>
      stage == NarrationAutomationStage.skipped ||
      stage == NarrationAutomationStage.done;
}

/// Drives the fully-automated location narration pipeline: enqueue an audio
/// job → nudge the narration worker to run it now → poll until it completes
/// or fails, emitting a [NarrationAutomationResult] at every stage.
///
/// WHY THIS EXISTS: the admin location editor shouldn't have to know about
/// `generation_jobs`, Edge Functions, or polling — it just listens to [run]'s
/// stream and shows whatever text comes through. The actual script + TTS
/// generation happens server-side in the `narration-worker` Edge Function
/// (`doLocationAudio`); this class only orchestrates and reports on it.
///
/// Every dependency is injected (not a real Supabase call) so this is fully
/// unit-testable — see [LocationRepository] for the real implementations used
/// in the app.
class LocationNarrationAutomation {
  LocationNarrationAutomation({
    required this.enqueue,
    required this.triggerWorker,
    required this.checkStatus,
    this.pollInterval = const Duration(seconds: 2),
    this.maxAttempts = 20, // ~40s at the default interval
  });

  /// Queues the audio job for [location]; returns the new job id, or null if
  /// it couldn't be queued (e.g. Supabase not configured).
  final Future<String?> Function(MasterLocation location) enqueue;

  /// Best-effort "run the worker now" call. A false/failed result isn't
  /// treated as fatal — the scheduled worker will pick the job up eventually.
  final Future<bool> Function() triggerWorker;

  /// Returns `{'status': ..., 'message': ...}` for a job id, or null if it
  /// can't be found (yet, or at all).
  final Future<Map<String, dynamic>?> Function(String jobId) checkStatus;

  final Duration pollInterval;
  final int maxAttempts;

  /// Runs the full flow for [location]. Emits progress updates and always
  /// ends with exactly one terminal result (skipped/done/failed) — never
  /// throws, so the UI never needs a try/catch around consuming this stream.
  Stream<NarrationAutomationResult> run(MasterLocation location) async* {
    if (location.hasAudio) {
      yield const NarrationAutomationResult(
        NarrationAutomationStage.skipped,
        'This location already has narration audio — nothing to generate.',
      );
      return;
    }

    yield const NarrationAutomationResult(
      NarrationAutomationStage.enqueuing,
      'Queuing narration job…',
    );

    String? jobId;
    try {
      jobId = await enqueue(location);
    } catch (e) {
      yield NarrationAutomationResult(
        NarrationAutomationStage.failed,
        'Could not queue the narration job: $e',
      );
      return;
    }
    if (jobId == null) {
      yield const NarrationAutomationResult(
        NarrationAutomationStage.failed,
        'Could not queue the narration job — Supabase is not configured.',
      );
      return;
    }

    yield const NarrationAutomationResult(
      NarrationAutomationStage.generating,
      'Generating narration script and voice…',
    );
    // Best-effort nudge; a false result just means the scheduled worker will
    // pick this job up on its own — not a reason to stop here.
    try {
      await triggerWorker();
    } catch (_) {}

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      await Future<void>.delayed(pollInterval);
      Map<String, dynamic>? job;
      try {
        job = await checkStatus(jobId);
      } catch (_) {
        job = null;
      }
      final status = (job?['status'] as String?) ?? '';
      switch (status) {
        case 'completed':
          yield const NarrationAutomationResult(
            NarrationAutomationStage.done,
            'Narration generated and attached.',
          );
          return;
        case 'failed':
          final reason = (job?['message'] as String?)?.trim();
          yield NarrationAutomationResult(
            NarrationAutomationStage.failed,
            (reason == null || reason.isEmpty)
                ? 'Narration generation failed.'
                : 'Narration generation failed: $reason',
          );
          return;
        default:
          // pending / running / not found yet — keep polling.
          continue;
      }
    }

    yield const NarrationAutomationResult(
      NarrationAutomationStage.failed,
      "Still processing — it's taking longer than expected. It will finish "
      'in the background; check back on this location shortly.',
    );
  }
}
