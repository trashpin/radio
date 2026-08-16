import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/events/models/local_event.dart';
import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';

/// Read access to `events` (migration 0043). Read-safe: returns [] when the
/// table doesn't exist yet or Supabase isn't configured, matching every other
/// content repository in this codebase — the EVENT tier simply never
/// activates until events are added, rather than erroring.
class EventRepository {
  const EventRepository();

  Future<List<LocalEvent>> all() async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('events')
          .select()
          .eq('active', true) as List;
      return rows.cast<Map<String, dynamic>>().map(LocalEvent.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }
}

final eventRepositoryProvider =
    Provider<EventRepository>((ref) => const EventRepository());

final eventsProvider = FutureProvider<List<LocalEvent>>((ref) {
  return ref.watch(eventRepositoryProvider).all();
});

/// One event paired with its live distance from the traveler.
class NearbyEvent {
  const NearbyEvent(this.event, this.distanceMeters);
  final LocalEvent event;
  final double distanceMeters;
}

/// Events happening today or later, within [maxMiles], nearest-first — the
/// EVENT tier's candidate list for the location-aware player. Reuses the
/// same GPS fix ([gpsControllerProvider]) every other proximity feature reads.
final nearbyEventsProvider = Provider<List<NearbyEvent>>((ref) {
  final loc = ref.watch(gpsControllerProvider).location;
  final all = ref.watch(eventsProvider).value ?? const [];
  if (loc == null) return const [];

  final today = DateTime.now();
  final todayDate = DateTime(today.year, today.month, today.day);
  const maxMiles = 20.0;
  const mile = 1609.344;

  final out = <NearbyEvent>[];
  for (final e in all) {
    if (!e.hasCoordinates) continue;
    if (e.eventDate != null && e.eventDate!.isBefore(todayDate)) continue;
    final m = GeoMath.distanceMeters(
        loc.latitude, loc.longitude, e.latitude!, e.longitude!);
    if (m > maxMiles * mile) continue;
    out.add(NearbyEvent(e, m));
  }
  out.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
  return out;
});
