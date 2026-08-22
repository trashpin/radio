import 'package:explorer_os_mobile/core/data/model.dart';

/// A geographic feature inside Ocala National Forest — springs, lakes,
/// trails, campgrounds, OHV areas, wildlife areas, and everything else
/// spec section 3 asks for. Deliberately a NEW, isolated model/table
/// (`forest_locations`, migration 0048) rather than a filtered view of the
/// existing `locations`/`MasterLocation` table used by Marion County
/// content — per the spec's explicit "keep the data isolated" and
/// "do not copy the existing Marion County database blindly" requirements.
///
/// [category] is free-form text, not an enum: the spec lists dozens of
/// possible feature types and explicitly says "do not limit the system to
/// only attractions," so a fixed enum would need a migration every time a
/// new category shows up in freshly-sourced data.
///
/// Every field spec section 8 asks for ("prepare for geofenced audio") is
/// already present, so this is compatible with the existing geofence/audio
/// architecture the moment that gets wired up — nothing here plays audio or
/// creates a geofence yet.
class ForestLocation implements Model {
  const ForestLocation({
    required this.id,
    required this.forestId,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    this.description,
    this.source,
    this.sourceUrl,
    this.geofenceRadiusMeters,
    this.narrationShort,
    this.narrationLong,
    this.audioUrl,
    this.tellMeMore,
    this.imageUrl,
    this.active = true,
  });

  @override
  final String id;
  final String forestId;
  final String name;
  final String category;
  final double latitude;
  final double longitude;
  final String? description;

  /// Attribution — never dropped, per the spec's "preserve source
  /// attribution" requirement.
  final String? source;
  final String? sourceUrl;

  final double? geofenceRadiusMeters;
  final String? narrationShort;
  final String? narrationLong;
  final String? audioUrl;
  final String? tellMeMore;
  final String? imageUrl;
  final bool active;

  bool get hasAudio => (audioUrl ?? '').trim().isNotEmpty;

  factory ForestLocation.fromJson(Json json) => ForestLocation(
        id: json['id']?.toString() ?? '',
        forestId: json['forest_id']?.toString() ?? '',
        name: (json['name'] ?? '') as String,
        category: (json['category'] ?? '') as String,
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        description: json['description'] as String?,
        source: json['source'] as String?,
        sourceUrl: json['source_url'] as String?,
        geofenceRadiusMeters: (json['geofence_radius_meters'] as num?)?.toDouble(),
        narrationShort: json['narration_short'] as String?,
        narrationLong: json['narration_long'] as String?,
        audioUrl: json['audio_url'] as String?,
        tellMeMore: json['tell_me_more'] as String?,
        imageUrl: json['image_url'] as String?,
        active: (json['active'] as bool?) ?? true,
      );
}
