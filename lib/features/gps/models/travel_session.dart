import 'package:explorer_os_mobile/core/data/model.dart';
import 'package:explorer_os_mobile/features/gps/models/travel_statistics.dart';

/// A single continuous journey/trip.
///
/// Groups everything about one outing: when it started/ended, whether it's
/// active, how many fixes it saw, and its cumulative [TravelStatistics]. Owned
/// by the TravelSessionService and persisted by the TravelRepository for a
/// future "trip history / summary" experience. USER-OWNED, so it provides
/// [toJson] for Supabase sync.
class TravelSession implements Model {
  const TravelSession({
    required this.id,
    required this.startedAt,
    this.endedAt,
    this.active = true,
    this.fixCount = 0,
    this.statistics = TravelStatistics.empty,
  });

  @override
  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final bool active;
  final int fixCount;
  final TravelStatistics statistics;

  Duration get duration => (endedAt ?? DateTime.now()).difference(startedAt);

  TravelSession copyWith({
    DateTime? endedAt,
    bool? active,
    int? fixCount,
    TravelStatistics? statistics,
  }) {
    return TravelSession(
      id: id,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      active: active ?? this.active,
      fixCount: fixCount ?? this.fixCount,
      statistics: statistics ?? this.statistics,
    );
  }

  Json toJson() => {
        'id': id,
        'started_at': startedAt.toIso8601String(),
        if (endedAt != null) 'ended_at': endedAt!.toIso8601String(),
        'active': active,
        'fix_count': fixCount,
        'distance_travelled_meters': statistics.distanceTravelledMeters,
        'max_speed_mps': statistics.maxSpeedMps,
        'parks_visited': statistics.parksVisited,
        'attractions_visited': statistics.attractionsVisited,
      };

  factory TravelSession.fromJson(Json json) => TravelSession(
        id: json['id']?.toString() ?? '',
        startedAt: DateTime.tryParse(json['started_at']?.toString() ?? '') ??
            DateTime.now(),
        endedAt: DateTime.tryParse(json['ended_at']?.toString() ?? ''),
        active: (json['active'] ?? false) as bool,
        fixCount: (json['fix_count'] as num?)?.toInt() ?? 0,
        statistics: TravelStatistics(
          distanceTravelledMeters:
              (json['distance_travelled_meters'] as num?)?.toDouble() ?? 0,
          maxSpeedMps: (json['max_speed_mps'] as num?)?.toDouble() ?? 0,
          parksVisited: (json['parks_visited'] as num?)?.toInt() ?? 0,
          attractionsVisited:
              (json['attractions_visited'] as num?)?.toInt() ?? 0,
        ),
      );
}
