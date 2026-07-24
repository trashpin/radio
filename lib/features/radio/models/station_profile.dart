import 'package:explorer_os_mobile/core/data/model.dart';

/// The editorial identity/personality of an intelligent radio station.
///
/// Read-only backend content (with a small in-app seed catalog as a fallback).
/// Describes WHO the station is; the concrete behavior (cadences) lives in
/// [StationRule], the playlist in `songs`, and IDs in [StationID] — all keyed by
/// [stationId]. This separation lets the app support hundreds of stations
/// data-driven.
class StationProfile implements Model {
  const StationProfile({
    required this.id,
    required this.stationId,
    required this.name,
    this.description,
    this.genre,
    this.mood,
    this.targetAudience,
    this.tags = const [],
  });

  @override
  final String id;
  final String stationId;
  final String name;
  final String? description;
  final String? genre;
  final String? mood;
  final String? targetAudience;
  final List<String> tags;

  factory StationProfile.fromJson(Json json) => StationProfile(
        id: json['id']?.toString() ?? '',
        stationId: json['station_id']?.toString() ?? json['id']?.toString() ?? '',
        name: (json['name'] ?? '') as String,
        description: json['description'] as String?,
        genre: json['genre'] as String?,
        mood: json['mood'] as String?,
        targetAudience: json['target_audience'] as String?,
        tags: (json['tags'] as List?)?.cast<String>() ?? const [],
      );
}
