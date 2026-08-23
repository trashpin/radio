import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';

class TestUserOption {
  const TestUserOption({required this.id, this.firstName, this.interests = const []});
  final String id;
  final String? firstName;
  final List<String> interests;

  String get label => (firstName ?? '').trim().isNotEmpty ? firstName!.trim() : id;
}

/// Admin access to the personalized event-alert matching engine
/// (`event-match-and-notify`). `profiles` RLS is self-only, so listing test
/// users has to go through the function (service-role access) rather than
/// a direct table query — see that function's own doc comment.
class EventNotificationRepository {
  const EventNotificationRepository();

  Future<List<TestUserOption>> listTestUsers() async {
    final res = await SupabaseService.client.functions
        .invoke('event-match-and-notify', body: {'listUsers': true})
        .timeout(const Duration(seconds: 30));
    final users = (res.data as Map?)?['users'] as List? ?? const [];
    return users.map((u) {
      final m = (u as Map).cast<String, dynamic>();
      return TestUserOption(
        id: m['id'] as String,
        firstName: m['firstName'] as String?,
        interests: (m['interests'] as List? ?? const []).map((e) => e.toString()).toList(),
      );
    }).toList();
  }

  /// Test mode: full pipeline (match -> script -> audio -> notification
  /// payload -> deep link) for ONE user. Never sends a real push.
  Future<Map<String, dynamic>> runTest(String eventId, String testUserId) async {
    final res = await SupabaseService.client.functions.invoke(
      'event-match-and-notify',
      body: {'eventId': eventId, 'testUserId': testUserId},
    ).timeout(const Duration(seconds: 60));
    return (res.data as Map?)?.cast<String, dynamic>() ?? const {};
  }

  /// Bulk mode: scores every user with interests set against this event and
  /// records the result — the step that should run whenever an event is
  /// approved. No audio/notification content generated here (see the
  /// function's own doc comment for why).
  Future<Map<String, dynamic>> runBulkMatch(String eventId) async {
    final res = await SupabaseService.client.functions
        .invoke('event-match-and-notify', body: {'eventId': eventId})
        .timeout(const Duration(seconds: 60));
    return (res.data as Map?)?.cast<String, dynamic>() ?? const {};
  }

  /// Admin monitoring: recent match/notification records across all users
  /// (spec: "Event / Potential matches / High-match users / Notifications
  /// generated..."). `event_matches` RLS already permits any authenticated
  /// session to read this internal table (same convention as
  /// discovered_events/event_sources), so no function round-trip needed.
  Future<List<Map<String, dynamic>>> recentMatches({int limit = 30}) async {
    final rows = await SupabaseService.client
        .from('event_matches')
        .select()
        .order('created_at', ascending: false)
        .limit(limit) as List;
    return rows.cast<Map<String, dynamic>>();
  }
}

final eventNotificationRepositoryProvider =
    Provider<EventNotificationRepository>((ref) => const EventNotificationRepository());
