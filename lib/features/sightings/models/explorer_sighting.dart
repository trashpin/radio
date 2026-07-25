import 'package:explorer_os_mobile/core/data/model.dart';
import 'package:explorer_os_mobile/features/sightings/models/sighting_category.dart';

/// A user observation ("I See Something"). Read/write content stored in the
/// `explorer_sightings` Supabase table. Designed to be future-ready: fields for
/// AI identification, photos, and citizen-science are present as placeholders.
class ExplorerSighting implements Model {
  const ExplorerSighting({
    required this.id,
    required this.category,
    this.userId,
    this.species,
    this.notes,
    this.latitude,
    this.longitude,
    this.elevationFt,
    this.destinationId,
    this.parkName,
    this.trail,
    this.travelDirection,
    this.weather,
    this.photoUrl,
    this.createdAt,
  });

  @override
  final String id;
  final SightingCategory category;
  final String? userId;
  final String? species;
  final String? notes;
  final double? latitude;
  final double? longitude;
  final int? elevationFt;
  final String? destinationId;
  final String? parkName;
  final String? trail;
  final String? travelDirection;
  final String? weather;

  /// Placeholder for a future uploaded photo URL.
  final String? photoUrl;
  final DateTime? createdAt;

  bool get hasCoordinates => latitude != null && longitude != null;

  factory ExplorerSighting.fromJson(Json json) => ExplorerSighting(
        id: (json['sighting_id'] ?? json['id'])?.toString() ?? '',
        category: SightingCategory.fromToken(json['category'] as String?),
        userId: json['user_id']?.toString(),
        species: json['species'] as String?,
        notes: json['notes'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        elevationFt: (json['elevation_ft'] as num?)?.toInt(),
        destinationId: json['destination_id']?.toString(),
        parkName: json['park_name'] as String?,
        trail: json['trail'] as String?,
        travelDirection: json['travel_direction'] as String?,
        weather: json['weather'] as String?,
        photoUrl: json['photo_url'] as String?,
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'].toString())
            : null,
      );

  /// Serializes for insert/update. Omits null keys so the DB applies defaults
  /// (e.g. `created_at`).
  Json toJson() => {
        'sighting_id': id,
        'category': category.token,
        if (userId != null) 'user_id': userId,
        if (species != null) 'species': species,
        if (notes != null) 'notes': notes,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (elevationFt != null) 'elevation_ft': elevationFt,
        if (destinationId != null) 'destination_id': destinationId,
        if (parkName != null) 'park_name': parkName,
        if (trail != null) 'trail': trail,
        if (travelDirection != null) 'travel_direction': travelDirection,
        if (weather != null) 'weather': weather,
        if (photoUrl != null) 'photo_url': photoUrl,
      };
}
