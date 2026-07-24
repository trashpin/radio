import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/music/models/gps_music_trigger.dart';

/// Read repository for [GPSMusicTrigger]s (geofenced songs).
class GPSMusicTriggerRepository
    extends SupabaseReadRepository<GPSMusicTrigger> {
  GPSMusicTriggerRepository({required super.client, super.connectivity})
      : super(
          table: SupabaseTables.gpsMusicTriggers,
          fromJson: GPSMusicTrigger.fromJson,
        );

  Future<List<GPSMusicTrigger>> byPark(String parkId) =>
      getWhere('park_id', parkId);
}

final gpsMusicTriggerRepositoryProvider =
    Provider<GPSMusicTriggerRepository>((ref) {
  return GPSMusicTriggerRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});
