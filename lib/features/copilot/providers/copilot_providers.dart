import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/copilot/data/copilot_profile_store.dart';
import 'package:explorer_os_mobile/features/copilot/data/copilot_session_memory.dart';
import 'package:explorer_os_mobile/features/copilot/models/copilot_event.dart';
import 'package:explorer_os_mobile/features/copilot/models/copilot_priority.dart';
import 'package:explorer_os_mobile/features/copilot/services/copilot_brain.dart';
import 'package:explorer_os_mobile/features/copilot/services/copilot_line_service.dart';
import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_state.dart';

final copilotBrainProvider = Provider<CopilotBrain>((ref) => const CopilotBrain());

final copilotLineServiceProvider =
    Provider<CopilotLineService>((ref) => const CopilotLineService());

/// One instance for the whole app session — deliberately NOT recreated per
/// screen/provider rebuild, since its whole job is remembering what's already
/// been said this trip. `CopilotController` resets it when a new trip starts.
final copilotSessionMemoryProvider =
    Provider<CopilotSessionMemory>((ref) => CopilotSessionMemory());

/// The single entry point every event source (GPS/geofencing wiring, the
/// trip tracker, What Is That?) calls: `notifyEvent(event)`. Internally runs
/// the full pipeline from the architecture diagram — EVENT → BRAIN →
/// PROFILE/CONTEXT → (OpenAI + ElevenLabs via `copilot-line`) → PERSONALITY
/// RESPONSE → EXISTING AUDIO PLAYER — reusing `requestInterruption` +
/// play-if-idle exactly like every other narration source in this app.
class CopilotController {
  CopilotController(this._ref);
  final Ref _ref;

  static const _maxRecentLines = 8;
  final List<String> _recentLines = [];

  Future<void> notifyEvent(CopilotEvent event) async {
    final brain = _ref.read(copilotBrainProvider);
    final profile = _ref.read(copilotProfileProvider);
    final memory = _ref.read(copilotSessionMemoryProvider);

    final decision = brain.decide(event: event, profile: profile, memory: memory);
    if (!decision.shouldSpeak) return;
    memory.markSpoken(event.dedupeKey);

    final tier = event.tier;
    final core = (event.coreText ?? '').trim();
    final corePlayedImmediately = tier.bypassesQuietWindow && core.isNotEmpty;

    // Safety/navigation instructions never wait on a network call — they
    // play the moment the brain says yes (spec §4: never confusing, never
    // buried under humor).
    if (corePlayedImmediately) {
      _play(text: core, audioUrl: null, tier: tier);
    }

    try {
      final line = await _ref.read(copilotLineServiceProvider).generate(
            event: event,
            profile: profile,
            recentLines: List.unmodifiable(_recentLines),
          );
      _rememberLine(line.text);
      if (!corePlayedImmediately) {
        _play(text: line.text, audioUrl: line.audioUrl, tier: tier);
      } else if (line.text.trim().isNotEmpty && line.text.trim() != core) {
        // A short trailing remark alongside the instruction that already
        // played — same independent requestInterruption pattern every other
        // director in radio_session_provider.dart already uses; the engine's
        // own priority/queue arbitration sequences it, no new coordination
        // logic needed here.
        _play(text: line.text, audioUrl: line.audioUrl, tier: CopilotPriorityTier.personality);
      }
    } catch (_) {
      // The deterministic core (if any) already played; a failed AI remark
      // is never worth surfacing as an error.
    }

    final placeId = event.placeId;
    if (placeId != null) {
      unawaited(_ref
          .read(copilotProfileProvider.notifier)
          .update((p) => p.withPlaceDiscussed(placeId)));
    }
  }

  void _rememberLine(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    _recentLines.add(t);
    while (_recentLines.length > _maxRecentLines) {
      _recentLines.removeAt(0);
    }
  }

  void _play({required String text, String? audioUrl, required CopilotPriorityTier tier}) {
    final priority = tier.playbackPriority;
    if (priority == null || text.trim().isEmpty) return;
    final radio = _ref.read(radioEngineControllerProvider.notifier);
    final hasAudio = (audioUrl ?? '').trim().isNotEmpty;
    radio.requestInterruption(
      AudioSegment(
        id: 'copilot:${DateTime.now().microsecondsSinceEpoch}',
        title: 'Copilot',
        artist: 'DJ Sunny',
        type: tier.interruptible
            ? AudioSegmentType.gpsNarration
            : AudioSegmentType.safetyWarning,
        priority: priority,
        audioUrl: hasAudio ? audioUrl : null,
        spokenText: hasAudio ? null : text,
        tags: const ['copilot'],
        interruptible: tier.interruptible,
        resumeAfter: true,
      ),
    );
    if (_ref.read(radioEngineControllerProvider).status != PlaybackStatus.playing) {
      radio.play();
    }
  }
}

final copilotControllerProvider =
    Provider<CopilotController>((ref) => CopilotController(ref));
