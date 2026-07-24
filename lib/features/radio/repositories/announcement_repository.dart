import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/radio/models/announcement.dart';

/// Read repository for [Announcement] content used by the AnnouncementScheduler.
class AnnouncementRepository extends SupabaseReadRepository<Announcement> {
  AnnouncementRepository({
    required super.client,
    super.connectivity,
  }) : super(
          table: SupabaseTables.announcements,
          fromJson: Announcement.fromJson,
        );

  Future<List<Announcement>> byStation(String stationId) =>
      getWhere('station_id', stationId);
}

final announcementRepositoryProvider = Provider<AnnouncementRepository>((ref) {
  return AnnouncementRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});
