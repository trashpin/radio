import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/narration/models/narration.dart';

/// Read/write repository for the `narrations` table.
///
/// Reads reuse the generic [SupabaseReadRepository]. The app only ever reads
/// (to stream stored audio); writes are used by the admin Narration Studio.
class NarrationRepository extends SupabaseReadRepository<Narration> {
  NarrationRepository({required super.client, super.connectivity})
      : super(table: SupabaseTables.narrations, fromJson: Narration.fromJson);

  /// All narrations for one content record.
  Future<List<Narration>> forContent(String contentId) async {
    final rows = await client
        .from(table)
        .select()
        .eq('content_id', contentId)
        .order('featured', ascending: false);
    return rows.map((r) => Narration.fromJson(r)).toList(growable: false);
  }

  /// The narration the app should play for a record: a published/approved one
  /// with audio, else any with audio, else any with a script.
  Future<Narration?> bestForContent(String contentId) async {
    final list = await forContent(contentId);
    if (list.isEmpty) return null;
    return list.firstWhere((n) => n.approved && n.hasAudio,
        orElse: () => list.firstWhere((n) => n.hasAudio,
            orElse: () => list.first));
  }

  Future<Narration> upsert(Narration n) async {
    final payload = n.toJson();
    final existing = n.id.isNotEmpty
        ? await client.from(table).select('id').eq('id', n.id).maybeSingle()
        : null;
    final rows = existing != null
        ? await client.from(table).update(payload).eq('id', n.id).select()
        : await client.from(table).insert(payload).select();
    return Narration.fromJson(rows.first);
  }
}

final narrationRepositoryProvider = Provider<NarrationRepository>((ref) {
  return NarrationRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});

/// Best playable narration for a content record (used by the app).
final bestNarrationProvider =
    FutureProvider.family<Narration?, String>((ref, contentId) {
  return ref.watch(narrationRepositoryProvider).bestForContent(contentId);
});
