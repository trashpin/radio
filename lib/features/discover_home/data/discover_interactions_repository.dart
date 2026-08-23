import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/discover_home/models/discoverable_item.dart';

/// Fire-and-forget interaction logging (migration 0053's
/// `discover_interactions`) — the architecture seam for future behavioral
/// personalization (spec: "items opened, saved, audio listened to,
/// categories viewed, events selected, places navigated to"). Deliberately
/// NOT read by the v1 recommendation scorer yet; this only writes.
class DiscoverInteractionsRepository {
  const DiscoverInteractionsRepository();

  Future<void> log(DiscoverableItem item, String interactionType) async {
    if (!SupabaseService.isConfigured) return;
    try {
      final uid = SupabaseService.client.auth.currentUser?.id;
      await SupabaseService.client.from('discover_interactions').insert({
        'user_id': uid,
        'item_type': item.narrationSubjectType,
        'item_id': item.id,
        'interaction_type': interactionType,
      });
    } catch (_) {
      // Logging must never block or surface an error to the visitor.
    }
  }
}

final discoverInteractionsRepositoryProvider =
    Provider<DiscoverInteractionsRepository>((ref) => const DiscoverInteractionsRepository());
