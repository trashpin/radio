import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/copilot/models/copilot_event.dart';
import 'package:explorer_os_mobile/features/copilot/models/copilot_profile.dart';

/// A generated (or fallback) spoken line — text, and a voiced audio URL when
/// ElevenLabs succeeded.
class CopilotLine {
  const CopilotLine({required this.text, this.audioUrl});
  final String text;
  final String? audioUrl;
  bool get hasAudio => (audioUrl ?? '').trim().isNotEmpty;
}

/// Client for the new `copilot-line` Supabase Edge Function — the first
/// SYNCHRONOUS OpenAI+ElevenLabs call in this app (everything else uses the
/// async `generation_jobs` queue). One request, one response: a fresh
/// sarcastic line plus its voiced audio URL, ready to play immediately.
///
/// Never leaves the copilot silent: if the network call fails, times out, or
/// comes back empty, [generate] falls back to a small local canned line
/// (or the event's own deterministic `coreText`, when set, which is always
/// preferred — the real safety/navigation instruction never depends on this
/// call succeeding in the first place; see `CopilotController`).
class CopilotLineService {
  const CopilotLineService();

  Future<CopilotLine> generate({
    required CopilotEvent event,
    required CopilotProfile profile,
    List<String> recentLines = const [],
  }) async {
    if (SupabaseService.isConfigured) {
      try {
        final res = await SupabaseService.client.functions.invoke(
          'copilot-line',
          body: {
            'eventType': event.type.name,
            'priorityTier': event.tier.name,
            'placeName': event.placeName,
            'typeLabel': event.typeLabel,
            'coreText': event.coreText,
            'facts': event.facts,
            'recentLines': recentLines,
            'profile': {
              'sarcasm': profile.sarcasm.name,
              'talkAmount': profile.talkAmount.name,
            },
            'maxWords': 40,
          },
        ).timeout(const Duration(seconds: 12));
        final data = res.data;
        if (data is Map) {
          final text = (data['text'] as String?)?.trim();
          final audioUrl = data['audioUrl'] as String?;
          if (text != null && text.isNotEmpty) {
            return CopilotLine(text: text, audioUrl: audioUrl);
          }
        }
      } catch (_) {
        // Fall through to the local fallback below.
      }
    }
    return _fallback(event);
  }

  CopilotLine _fallback(CopilotEvent event) {
    final core = (event.coreText ?? '').trim();
    if (core.isNotEmpty) return CopilotLine(text: core);
    final lines = _fallbackLines[event.type] ?? const ["Well, here we are."];
    final pick = lines[DateTime.now().microsecondsSinceEpoch % lines.length];
    return CopilotLine(text: pick);
  }

  static const Map<CopilotEventType, List<String>> _fallbackLines = {
    CopilotEventType.tripStarted: [
      "Alright, let's see where this goes.",
      "Buckle up. Let's go.",
    ],
    CopilotEventType.enteringTown: [
      "Welcome to town. Let's see what kind of trouble we can find.",
    ],
    CopilotEventType.enteringCounty: [
      "New county. New questionable decisions.",
    ],
    CopilotEventType.missedTurn: [
      "You missed the turn. Impressive.",
    ],
    CopilotEventType.recalculating: [
      "Fine. We'll do it your way. Recalculating.",
    ],
    CopilotEventType.arrived: [
      "Well, we made it. Against several odds.",
    ],
    CopilotEventType.approachingInterestingLocation: [
      "There's something interesting coming up.",
    ],
    CopilotEventType.whatIsThatConfirmed: [
      "Oh, you want to know what THAT is? Alright, let's find out.",
    ],
  };
}
