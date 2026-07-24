import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/shared/models/destination.dart';

/// Data-access layer for destinations.
///
/// Now built on the generic [SupabaseReadRepository], so all the query, caching,
/// and error-handling plumbing is inherited (no duplication). This class adds
/// only destination-specific concerns — here, alphabetized listing via
/// [fetchDestinations]. The app is read-only for content, so it exposes reads
/// only.
class DestinationRepository extends SupabaseReadRepository<Destination> {
  DestinationRepository({
    required super.client,
    super.connectivity,
  }) : super(
          table: SupabaseTables.destinations,
          fromJson: Destination.fromJson,
        );

  /// All destinations, alphabetized by name (kept for backward compatibility
  /// with the Explore screen).
  Future<List<Destination>> fetchDestinations() async {
    final items = await getAll();
    return [...items]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
}

/// Provides a [DestinationRepository] wired to the shared Supabase client and
/// connectivity service.
final destinationRepositoryProvider = Provider<DestinationRepository>((ref) {
  return DestinationRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});
