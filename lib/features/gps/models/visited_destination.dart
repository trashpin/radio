import 'package:explorer_os_mobile/core/data/model.dart';

/// A destination the user has already visited this session (or historically).
///
/// USER-OWNED, so it provides [toJson] for syncing to Supabase. Powers "already
/// visited" filtering in detection and a future trips/history view.
class VisitedDestination implements Model {
  const VisitedDestination({
    required this.id,
    required this.destinationId,
    required this.visitedAt,
    this.name,
    this.parkId,
  });

  @override
  final String id;
  final String destinationId;
  final DateTime visitedAt;
  final String? name;
  final String? parkId;

  factory VisitedDestination.fromJson(Json json) => VisitedDestination(
        id: json['id']?.toString() ?? '',
        destinationId: json['destination_id']?.toString() ?? '',
        visitedAt: DateTime.tryParse(json['visited_at']?.toString() ?? '') ??
            DateTime.now(),
        name: json['name'] as String?,
        parkId: json['park_id']?.toString(),
      );

  Json toJson() => {
        'id': id,
        'destination_id': destinationId,
        'visited_at': visitedAt.toIso8601String(),
        if (name != null) 'name': name,
        if (parkId != null) 'park_id': parkId,
      };
}
