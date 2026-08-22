import 'package:explorer_os_mobile/features/copilot/data/copilot_session_memory.dart';
import 'package:explorer_os_mobile/features/copilot/models/copilot_event.dart';
import 'package:explorer_os_mobile/features/copilot/models/copilot_priority.dart';
import 'package:explorer_os_mobile/features/copilot/models/copilot_profile.dart';

enum CopilotAction { speak, staySilent }

/// The brain's verdict on one [CopilotEvent] — pure data, no side effects.
/// `CopilotLineService`/the audio-playing glue act on this; `CopilotBrain`
/// itself never touches audio, network, or storage.
class CopilotDecision {
  const CopilotDecision({required this.action, this.event, this.reason = ''});
  final CopilotAction action;
  final CopilotEvent? event;
  final String reason;

  bool get shouldSpeak => action == CopilotAction.speak && event != null;
}

/// The central decision layer (spec §11's "Copilot Brain"): given an event,
/// the traveler's profile, and this trip's session memory, decides whether
/// the copilot should speak at all. Deliberately synchronous and side-effect
/// free — no network, no audio, no OpenAI/ElevenLabs calls — so it's fully
/// unit-testable and matches the spec's own "test text responses before
/// generating audio" instinct one level earlier: test the DECISION before
/// generating any text at all.
///
/// Rules, in order:
/// 1. Never repeat the exact same thing twice in a trip (session memory).
/// 2. Safety/navigation always speaks — never buried under a quiet window or
///    humor-driven suppression (spec §2/§4).
/// 3. Background-tier events never speak.
/// 4. Informational events are skipped when the traveler has shown low
///    interest in that topic (spec §6's "repeatedly skips → lower priority").
/// 5. Everything else is gated by a quiet window so the copilot doesn't
///    narrate constantly — tuned by the profile's own talk-amount preference.
class CopilotBrain {
  const CopilotBrain({this.baseQuietWindow = const Duration(seconds: 60)});

  final Duration baseQuietWindow;

  CopilotDecision decide({
    required CopilotEvent event,
    required CopilotProfile profile,
    required CopilotSessionMemory memory,
  }) {
    if (memory.hasSpoken(event.dedupeKey)) {
      return const CopilotDecision(
        action: CopilotAction.staySilent,
        reason: 'already said this trip',
      );
    }

    final tier = event.tier;

    if (tier.bypassesQuietWindow) {
      return CopilotDecision(
        action: CopilotAction.speak,
        event: event,
        reason: '${tier.name} always speaks',
      );
    }

    if (tier == CopilotPriorityTier.background) {
      return const CopilotDecision(
        action: CopilotAction.staySilent,
        reason: 'background tier',
      );
    }

    if (tier == CopilotPriorityTier.informational) {
      final topic = topicForTypeLabel(event.typeLabel);
      if (topic != null && profile.interestIn(topic) == InterestLevel.low) {
        return CopilotDecision(
          action: CopilotAction.staySilent,
          reason: 'low interest in ${topic.name}',
        );
      }
    }

    final sinceLast = memory.sinceLastSpoken;
    final quiet = _quietWindowFor(profile);
    if (sinceLast != null && sinceLast < quiet) {
      return CopilotDecision(
        action: CopilotAction.staySilent,
        reason: 'quiet window (${quiet.inSeconds}s)',
      );
    }

    return CopilotDecision(action: CopilotAction.speak, event: event, reason: 'eligible');
  }

  Duration _quietWindowFor(CopilotProfile profile) => switch (profile.talkAmount) {
        InterestLevel.low => baseQuietWindow * 2,
        InterestLevel.medium => baseQuietWindow,
        InterestLevel.high =>
          Duration(seconds: (baseQuietWindow.inSeconds / 2).round()),
      };
}
