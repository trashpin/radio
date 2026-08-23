import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';

/// One row of `event_sources` (migration 0055) — a source's config +
/// its most recent run stats.
class EventSourceRow {
  const EventSourceRow({
    required this.id,
    required this.name,
    required this.sourceKey,
    required this.sourceType,
    this.sourceUrl,
    required this.enabled,
    required this.autoPublish,
    this.lastCheckedAt,
    this.lastSuccessAt,
    this.lastError,
    this.lastRunDiscovered = 0,
    this.lastRunNew = 0,
    this.lastRunDuplicates = 0,
    this.lastRunNeedsReview = 0,
    this.lastRunRejected = 0,
  });

  final String id;
  final String name;
  final String sourceKey;
  final String sourceType;
  final String? sourceUrl;
  final bool enabled;
  final bool autoPublish;
  final DateTime? lastCheckedAt;
  final DateTime? lastSuccessAt;
  final String? lastError;
  final int lastRunDiscovered;
  final int lastRunNew;
  final int lastRunDuplicates;
  final int lastRunNeedsReview;
  final int lastRunRejected;

  factory EventSourceRow.fromJson(Map<String, dynamic> j) => EventSourceRow(
        id: j['id'] as String,
        name: j['name'] as String,
        sourceKey: j['source_key'] as String,
        sourceType: j['source_type'] as String,
        sourceUrl: j['source_url'] as String?,
        enabled: (j['enabled'] ?? false) as bool,
        autoPublish: (j['auto_publish'] ?? false) as bool,
        lastCheckedAt: DateTime.tryParse('${j['last_checked_at']}'),
        lastSuccessAt: DateTime.tryParse('${j['last_success_at']}'),
        lastError: j['last_error'] as String?,
        lastRunDiscovered: (j['last_run_discovered'] ?? 0) as int,
        lastRunNew: (j['last_run_new'] ?? 0) as int,
        lastRunDuplicates: (j['last_run_duplicates'] ?? 0) as int,
        lastRunNeedsReview: (j['last_run_needs_review'] ?? 0) as int,
        lastRunRejected: (j['last_run_rejected'] ?? 0) as int,
      );
}

/// One row of `discovered_events` (migration 0055) — a normalized candidate
/// awaiting (or past) review.
class DiscoveredEventRow {
  const DiscoveredEventRow({
    required this.id,
    required this.sourceId,
    this.sourceUrl,
    required this.status,
    this.rejectionReason,
    this.matchConfidence,
    required this.name,
    this.description,
    this.startDate,
    this.startTime,
    this.venueName,
    this.address,
    this.city,
    this.county,
    this.latitude,
    this.longitude,
    this.website,
    this.ticketUrl,
    this.imageUrl,
    this.costInfo,
    this.category,
    this.interestTags = const [],
    this.timeOfDay,
    this.experienceTags = const [],
  });

  final String id;
  final String sourceId;
  final String? sourceUrl;
  final String status;
  final String? rejectionReason;
  final double? matchConfidence;
  final String name;
  final String? description;
  final DateTime? startDate;
  final String? startTime;
  final String? venueName;
  final String? address;
  final String? city;
  final String? county;
  final double? latitude;
  final double? longitude;
  final String? website;
  final String? ticketUrl;
  final String? imageUrl;
  final String? costInfo;
  final String? category;
  final List<String> interestTags;

  /// Nightlife/evening-entertainment expansion (migration 0057) — see
  /// [LocalEvent.timeOfDay]/[LocalEvent.experienceTags] for the same fields
  /// on a published event.
  final String? timeOfDay;
  final List<String> experienceTags;

  bool get isEveningOrLater => timeOfDay == 'evening' || timeOfDay == 'late_night';

  factory DiscoveredEventRow.fromJson(Map<String, dynamic> j) => DiscoveredEventRow(
        id: j['id'] as String,
        sourceId: j['source_id'] as String,
        sourceUrl: j['source_url'] as String?,
        status: j['status'] as String,
        rejectionReason: j['rejection_reason'] as String?,
        matchConfidence: (j['match_confidence'] as num?)?.toDouble(),
        name: j['name'] as String,
        description: j['description'] as String?,
        startDate: j['start_date'] == null ? null : DateTime.tryParse(j['start_date'].toString()),
        startTime: j['start_time'] as String?,
        venueName: j['venue_name'] as String?,
        address: j['address'] as String?,
        city: j['city'] as String?,
        county: j['county'] as String?,
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        website: j['website'] as String?,
        ticketUrl: j['ticket_url'] as String?,
        imageUrl: j['image_url'] as String?,
        costInfo: j['cost_info'] as String?,
        category: j['category'] as String?,
        interestTags: j['interest_tags'] is List
            ? (j['interest_tags'] as List).map((e) => e.toString()).toList()
            : const [],
        timeOfDay: j['time_of_day'] as String?,
        experienceTags: j['experience_tags'] is List
            ? (j['experience_tags'] as List).map((e) => e.toString()).toList()
            : const [],
      );
}

/// Admin access to the Marion County Event Discovery Engine (migration 0055
/// + the `marion-event-discovery` edge function). The engine itself never
/// writes to `events` for a reviewed source — [approve] is the one place
/// that promotes a candidate, mirroring exactly what the edge function does
/// for an `auto_publish` source.
class EventDiscoveryRepository {
  const EventDiscoveryRepository();

  Future<List<EventSourceRow>> sources() async {
    if (!SupabaseService.isConfigured) return const [];
    final rows = await SupabaseService.client
        .from('event_sources')
        .select()
        .order('name') as List;
    return rows.cast<Map<String, dynamic>>().map(EventSourceRow.fromJson).toList();
  }

  /// Everything still awaiting a human decision — both the engine's
  /// low-confidence "needs_review" rows AND its clean "verified" matches.
  /// A non-auto_publish source (Ticketmaster today) never promotes a
  /// "verified" row on its own, so without including it here those rows
  /// would pass every check and then sit invisible forever.
  Future<List<DiscoveredEventRow>> needsReview() async {
    if (!SupabaseService.isConfigured) return const [];
    final rows = await SupabaseService.client
        .from('discovered_events')
        .select()
        .inFilter('status', ['needs_review', 'verified'])
        .order('created_at', ascending: false) as List;
    return rows.cast<Map<String, dynamic>>().map(DiscoveredEventRow.fromJson).toList();
  }

  /// Runs the engine. [dryRun] true (the default) writes nothing — use it to
  /// see counts before trusting a source.
  Future<Map<String, dynamic>> runDiscovery({
    bool dryRun = true,
    List<String>? sourceKeys,
  }) async {
    final res = await SupabaseService.client.functions.invoke(
      'marion-event-discovery',
      body: {
        'dryRun': dryRun,
        if (sourceKeys != null && sourceKeys.isNotEmpty) 'sourceKeys': sourceKeys,
      },
    ).timeout(const Duration(seconds: 60));
    return (res.data as Map?)?.cast<String, dynamic>() ?? const {};
  }

  /// Publishes a reviewed candidate into `events` — the ONE point (besides
  /// an auto_publish source's own automatic path) where a discovered_events
  /// row becomes a real event.
  Future<void> approve(DiscoveredEventRow row) async {
    final inserted = await SupabaseService.client.from('events').insert({
      'name': row.name,
      'description': row.description,
      'image_url': row.imageUrl,
      'latitude': row.latitude,
      'longitude': row.longitude,
      'county': row.county ?? 'Marion',
      'city': row.city,
      'event_date': row.startDate?.toIso8601String().split('T').first,
      'start_time': row.startTime,
      'external_website': row.website,
      'ticket_url': row.ticketUrl,
      'cost_info': row.costInfo,
      'category': row.category,
      'interest_tags': row.interestTags,
      'time_of_day': row.timeOfDay,
      'experience_tags': row.experienceTags,
      'active': true,
    }).select('id').single();

    await SupabaseService.client.from('discovered_events').update({
      'status': 'published',
      'published_event_id': inserted['id'],
    }).eq('id', row.id);

    // Personalized voiced event alerts: score this newly-approved event
    // against every user with interests set (spec: "when a new event is
    // added to the approved database, determine whether it's a match").
    // Best-effort — a matching failure must never block the approval that
    // already succeeded above.
    try {
      await SupabaseService.client.functions.invoke(
        'event-match-and-notify',
        body: {'eventId': inserted['id']},
      ).timeout(const Duration(seconds: 30));
    } catch (_) {}
  }

  Future<void> reject(DiscoveredEventRow row, {String reason = 'manual_admin_reject'}) async {
    await SupabaseService.client.from('discovered_events').update({
      'status': 'rejected',
      'rejection_reason': reason,
    }).eq('id', row.id);
  }
}

final eventDiscoveryRepositoryProvider =
    Provider<EventDiscoveryRepository>((ref) => const EventDiscoveryRepository());

class EventDiscoveryRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final eventDiscoveryRefreshProvider =
    NotifierProvider<EventDiscoveryRefresh, int>(EventDiscoveryRefresh.new);

final eventSourcesProvider = FutureProvider<List<EventSourceRow>>((ref) {
  ref.watch(eventDiscoveryRefreshProvider);
  return ref.watch(eventDiscoveryRepositoryProvider).sources();
});

final discoveredEventsNeedingReviewProvider = FutureProvider<List<DiscoveredEventRow>>((ref) {
  ref.watch(eventDiscoveryRefreshProvider);
  return ref.watch(eventDiscoveryRepositoryProvider).needsReview();
});
