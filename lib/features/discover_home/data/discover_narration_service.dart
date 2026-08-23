import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/discover_home/models/discoverable_item.dart';

/// One generated (or cached) narration result from the `discover-narration`
/// Edge Function.
class DiscoverNarrationResult {
  const DiscoverNarrationResult({required this.text, this.audioUrl});
  final String text;
  final String? audioUrl;
  bool get hasAudio => (audioUrl ?? '').trim().isNotEmpty;
}

/// Client for `discover-narration` — the same OpenAI+ElevenLabs pattern
/// `forest-tour`/`forest-discovery` already use, reused for Discover items
/// instead of a new integration. [kind] 'short' backs "🎧 Hear About It",
/// 'long' backs "Tell Me More" when no substantive recorded/written history
/// already exists for the item.
class DiscoverNarrationService {
  const DiscoverNarrationService();

  Future<DiscoverNarrationResult?> requestFor(
    DiscoverableItem item, {
    required String kind,
    Set<String> matchedInterests = const {},
  }) async {
    if (!SupabaseService.isConfigured) return null;
    try {
      final res = await SupabaseService.client.functions.invoke(
        'discover-narration',
        body: {
          'subjectType': item.narrationSubjectType,
          'subjectId': item.id,
          'kind': kind,
          'name': item.title,
          if (item.category != null) 'category': item.category,
          if ((item.teaser ?? '').isNotEmpty) 'description': item.teaser,
          if (item.context.distanceLabel != null) 'distanceLabel': item.context.distanceLabel,
          if (matchedInterests.isNotEmpty) 'matchedInterests': matchedInterests.toList(),
        },
      ).timeout(const Duration(seconds: 45));
      final data = res.data;
      if (data is Map) {
        final text = (data['text'] as String?)?.trim();
        if (text != null && text.isNotEmpty) {
          return DiscoverNarrationResult(text: text, audioUrl: data['audioUrl'] as String?);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

final discoverNarrationServiceProvider =
    Provider<DiscoverNarrationService>((ref) => const DiscoverNarrationService());
