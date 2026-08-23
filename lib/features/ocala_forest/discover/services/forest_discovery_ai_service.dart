import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';

/// The AI's photo-identification suggestion (spec §3/§4) — always a
/// suggestion, never presented by this class or its callers as a fact.
class DiscoveryIdentification {
  const DiscoveryIdentification({
    required this.identification,
    required this.scientificName,
    required this.confidence,
    required this.explanation,
    required this.caveats,
  });

  /// Null when the AI genuinely can't suggest anything — never filled with
  /// a guess just to have a value.
  final String? identification;
  final String? scientificName;

  /// "high" | "medium" | "low".
  final String confidence;
  final String explanation;
  final String caveats;

  bool get hasSuggestion => (identification ?? '').trim().isNotEmpty;

  factory DiscoveryIdentification.fromJson(Map<dynamic, dynamic> json) =>
      DiscoveryIdentification(
        identification: json['identification'] as String?,
        scientificName: json['scientificName'] as String?,
        confidence: (json['confidence'] as String?) ?? 'low',
        explanation: (json['explanation'] as String?) ?? '',
        caveats: (json['caveats'] as String?) ?? '',
      );
}

/// The spoken "Tell Me About It" explanation (spec §7).
class DiscoveryNarration {
  const DiscoveryNarration({required this.text, this.audioUrl});
  final String text;
  final String? audioUrl;
  bool get hasAudio => (audioUrl ?? '').trim().isNotEmpty;
}

/// Client for the `forest-discovery` Edge Function — DISCOVER's AI photo
/// identification + spoken explanation. Unlike `CopilotLineService`
/// (which always falls back to a canned line, since it's just personality
/// banter), a failure here returns null rather than inventing a plausible-
/// looking result — the caller must show a real "couldn't identify this,
/// try again" state, never a fabricated suggestion.
class ForestDiscoveryAiService {
  const ForestDiscoveryAiService();

  Future<DiscoveryIdentification?> identify({
    required String imageBase64,
    required String mimeType,
    required String category,
    String? subtype,
  }) async {
    if (!SupabaseService.isConfigured) return null;
    try {
      final res = await SupabaseService.client.functions.invoke(
        'forest-discovery',
        body: {
          'action': 'identify',
          'imageBase64': imageBase64,
          'mimeType': mimeType,
          'category': category,
          'subtype': subtype,
        },
      ).timeout(const Duration(seconds: 45));
      final data = res.data;
      if (data is Map) return DiscoveryIdentification.fromJson(data);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<DiscoveryNarration?> narrate({
    required String? identification,
    String? scientificName,
    String? category,
    String? aiExplanation,
    String? userNotes,
  }) async {
    if (!SupabaseService.isConfigured) return null;
    try {
      final res = await SupabaseService.client.functions.invoke(
        'forest-discovery',
        body: {
          'action': 'narrate',
          'identification': identification,
          'scientificName': scientificName,
          'category': category,
          'aiExplanation': aiExplanation,
          'userNotes': userNotes,
        },
      ).timeout(const Duration(seconds: 30));
      final data = res.data;
      if (data is Map) {
        final text = (data['text'] as String?)?.trim();
        if (text != null && text.isNotEmpty) {
          return DiscoveryNarration(text: text, audioUrl: data['audioUrl'] as String?);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

final forestDiscoveryAiServiceProvider =
    Provider<ForestDiscoveryAiService>((ref) => const ForestDiscoveryAiService());
