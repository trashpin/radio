import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';

/// The Copilot's OWN willingness-to-speak priority — a separate concern from
/// [PlaybackPriority] (which governs interruption order inside the audio
/// engine). Every event gets exactly one tier; safety/navigation are the only
/// tiers that bypass the quiet window and per-trip repeat suppression.
enum CopilotPriorityTier { safety, navigation, informational, personality, background }

extension CopilotPriorityTierX on CopilotPriorityTier {
  /// Maps onto the EXISTING [PlaybackPriority] ladder — no new priority
  /// values were added. `null` means "never becomes an AudioSegment at all".
  PlaybackPriority? get playbackPriority => switch (this) {
        CopilotPriorityTier.safety => PlaybackPriority.safetyWarning,
        CopilotPriorityTier.navigation => PlaybackPriority.safetyWarning,
        CopilotPriorityTier.informational => PlaybackPriority.gpsNarration,
        CopilotPriorityTier.personality => PlaybackPriority.gpsNarration,
        CopilotPriorityTier.background => null,
      };

  /// Safety/navigation lines always play immediately — never buried under
  /// humor, never gated by "the copilot already spoke recently".
  bool get bypassesQuietWindow =>
      this == CopilotPriorityTier.safety || this == CopilotPriorityTier.navigation;

  /// Whether a higher-priority segment may cut this one off mid-sentence.
  /// Safety/navigation instructions are never interruptible.
  bool get interruptible =>
      this != CopilotPriorityTier.safety && this != CopilotPriorityTier.navigation;
}
