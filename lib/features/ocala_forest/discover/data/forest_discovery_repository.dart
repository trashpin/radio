import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/ocala_forest/discover/models/forest_discovery_report.dart';

/// Read repository for [ForestDiscoveryReport] — same
/// `SupabaseReadRepository<T>` shape as every other repository, pointed at
/// the `forest_discovery_reports_public` VIEW (never the base table, which
/// this app's anon/authenticated client cannot read at all — see migration
/// 0051).
class ForestDiscoveryRepository extends SupabaseReadRepository<ForestDiscoveryReport> {
  ForestDiscoveryRepository({
    required super.client,
    super.connectivity,
  }) : super(
          table: SupabaseTables.forestDiscoveryReportsPublic,
          fromJson: ForestDiscoveryReport.fromJson,
        );
}

final forestDiscoveryRepositoryProvider = Provider<ForestDiscoveryRepository>((ref) {
  return ForestDiscoveryRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});
