import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/discover_home/models/discoverable_item.dart';
import 'package:explorer_os_mobile/features/events/data/event_repository.dart';
import 'package:explorer_os_mobile/features/gps/providers/gps_status_provider.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';

/// Resolves a single event (by id) into a [DiscoverableItem] for the
/// notification/deep-link flow (`/discover-event/:id`) — a visitor tapping
/// a push notification needs the exact event, not whatever
/// `discoverAllItemsProvider`'s full county-wide load happens to contain
/// yet. Reuses [EventRepository.byId] and the existing
/// `discoverItemFromEvent` normalizer; no second content model.
final discoverEventByIdProvider =
    FutureProvider.family<DiscoverableItem?, String>((ref, id) async {
  final event = await ref.watch(eventRepositoryProvider).byId(id);
  if (event == null) return null;

  double distanceMeters = 0;
  if (event.hasCoordinates) {
    final gps = ref.watch(gpsStatusProvider);
    if (gps.latitude != null && gps.longitude != null) {
      distanceMeters = GeoMath.distanceMeters(
        gps.latitude!, gps.longitude!, event.latitude!, event.longitude!,
      );
    }
  }
  return discoverItemFromEvent(NearbyEvent(event, distanceMeters));
});

/// The signed-in visitor's own match record for this event (if the
/// matching engine has scored it) — drives the "🎧 WE FOUND THIS FOR YOU /
/// Because you like: ..." banner when an event was opened via a
/// notification (or the admin test-mode page). Absent entirely for a
/// visitor who opened the event some other way (browsing NEAR YOU, etc.),
/// which is the normal, non-error case.
final discoverEventMatchProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, eventId) async {
  if (!SupabaseService.isConfigured) return null;
  final uid = SupabaseService.client.auth.currentUser?.id;
  if (uid == null) return null;
  try {
    return await SupabaseService.client
        .from('event_matches')
        .select()
        .eq('event_id', eventId)
        .eq('user_id', uid)
        .maybeSingle();
  } catch (_) {
    return null;
  }
});
