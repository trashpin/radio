import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/radio/models/station_rule.dart';

/// Read repository for [StationRule] content consumed by the schedulers.
class StationRuleRepository extends SupabaseReadRepository<StationRule> {
  StationRuleRepository({
    required super.client,
    super.connectivity,
  }) : super(
          table: SupabaseTables.stationRules,
          fromJson: StationRule.fromJson,
        );

  /// The rule for a specific station (first match), or null if none defined.
  Future<StationRule?> forStation(String stationId) async {
    final rules = await getWhere('station_id', stationId);
    return rules.isEmpty ? null : rules.first;
  }
}

final stationRuleRepositoryProvider = Provider<StationRuleRepository>((ref) {
  return StationRuleRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});
