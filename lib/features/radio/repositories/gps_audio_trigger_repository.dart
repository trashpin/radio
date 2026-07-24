import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/radio/models/gps_audio_trigger.dart';

/// Read repository for [GPSAudioTrigger] content.
///
/// Loaded by the [GPSAudioScheduler] to PREPARE for GPS. No location evaluation
/// happens yet — this just makes the geofenced triggers available.
class GPSAudioTriggerRepository extends SupabaseReadRepository<GPSAudioTrigger> {
  GPSAudioTriggerRepository({
    required super.client,
    super.connectivity,
  }) : super(
          table: SupabaseTables.gpsAudioTriggers,
          fromJson: GPSAudioTrigger.fromJson,
        );

  Future<List<GPSAudioTrigger>> byPark(String parkId) =>
      getWhere('park_id', parkId);
}

final gpsAudioTriggerRepositoryProvider =
    Provider<GPSAudioTriggerRepository>((ref) {
  return GPSAudioTriggerRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});
