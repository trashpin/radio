import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FileOptions, PostgrestException;
import 'dart:typed_data';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/events/models/local_event.dart';
import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';

/// Read/write access to `events` (migration 0043). Read-safe: returns [] when
/// the table doesn't exist yet or Supabase isn't configured, matching every
/// other content repository in this codebase — the EVENT tier simply never
/// activates until events are added, rather than erroring.
class EventRepository {
  const EventRepository();

  static const String bucket = 'media';

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

  /// Every event regardless of [LocalEvent.active] — the admin list, so a
  /// deactivated event is still visible/editable there.
  Future<List<LocalEvent>> adminAll() async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('events')
          .select()
          .order('event_date', ascending: true) as List;
      return rows.cast<Map<String, dynamic>>().map(LocalEvent.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> create(Map<String, dynamic> row) => _resilient(
        row,
        (r) => SupabaseService.client.from('events').insert(r),
      );

  Future<void> update(String id, Map<String, dynamic> fields) => _resilient(
        fields,
        (r) => SupabaseService.client.from('events').update(r).eq('id', id),
      );

  Future<void> delete(String id) =>
      SupabaseService.client.from('events').delete().eq('id', id);

  /// Runs a write, and if it fails only because a column isn't in the schema
  /// cache yet, drops that column and retries (same pattern as `nearby_gems`
  /// and `counties`).
  Future<void> _resilient(
    Map<String, dynamic> row,
    Future<void> Function(Map<String, dynamic>) run,
  ) async {
    var current = Map<String, dynamic>.from(row);
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        await run(current);
        return;
      } on PostgrestException catch (e) {
        final col = _missingColumn(e.message);
        if (col == null || !current.containsKey(col)) rethrow;
        current.remove(col);
      }
    }
    await run(current);
  }

  static String? _missingColumn(String message) {
    final m = RegExp(r"'([a-zA-Z0-9_]+)' column").firstMatch(message);
    return m?.group(1);
  }

  /// Uploads an event image to the `media` bucket and returns its public URL.
  Future<String> uploadImage(
    Uint8List bytes,
    String filename, {
    String contentType = 'image/jpeg',
  }) async {
    final client = SupabaseService.client;
    final slug = filename.toLowerCase().replaceAll(RegExp(r'[^a-z0-9.]+'), '_');
    final path = 'events/${DateTime.now().millisecondsSinceEpoch}_$slug';
    await client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );
    return client.storage.from(bucket).getPublicUrl(path);
  }
}

final eventRepositoryProvider =
    Provider<EventRepository>((ref) => const EventRepository());

class EventsRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final eventsRefreshProvider =
    NotifierProvider<EventsRefresh, int>(EventsRefresh.new);

final eventsProvider = FutureProvider<List<LocalEvent>>((ref) {
  ref.watch(eventsRefreshProvider);
  return ref.watch(eventRepositoryProvider).all();
});

/// Every event (admin list) — see [EventRepository.adminAll].
final adminEventsProvider = FutureProvider<List<LocalEvent>>((ref) {
  ref.watch(eventsRefreshProvider);
  return ref.watch(eventRepositoryProvider).adminAll();
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
