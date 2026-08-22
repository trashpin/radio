import 'package:explorer_os_mobile/core/data/model.dart';
import 'package:explorer_os_mobile/features/ocala_forest/services/point_in_polygon.dart';

/// One ring (a closed loop of vertices) of a polygon part.
class ForestPolygonRing {
  const ForestPolygonRing(this.points);
  final List<LatLngPoint> points;

  /// Parses a GeoJSON-style ring: `[[lng, lat], [lng, lat], ...]`.
  factory ForestPolygonRing.fromGeoJson(List<dynamic> coords) =>
      ForestPolygonRing([
        for (final c in coords)
          (lat: (c[1] as num).toDouble(), lng: (c[0] as num).toDouble()),
      ]);
}

/// One contiguous part of a (possibly multi-part) forest boundary — an outer
/// ring plus any holes cut out of it. A real national forest boundary is
/// rarely a single simple polygon: Ocala National Forest alone has several
/// small detached parcels alongside its two main bodies (Lake George and
/// Seminole Ranger Districts), which is exactly why this supports multiple
/// parts rather than one ring.
class ForestPolygonPart {
  const ForestPolygonPart({required this.outer, this.holes = const []});
  final ForestPolygonRing outer;
  final List<ForestPolygonRing> holes;

  bool contains(double lat, double lng) {
    if (!pointInRing(lat, lng, outer.points)) return false;
    for (final hole in holes) {
      if (pointInRing(lat, lng, hole.points)) return false;
    }
    return true;
  }

  /// Parses a GeoJSON-style polygon part: `[outerRing, hole1, hole2, ...]`.
  factory ForestPolygonPart.fromGeoJson(List<dynamic> rings) =>
      ForestPolygonPart(
        outer: ForestPolygonRing.fromGeoJson(rings.first as List),
        holes: [
          for (final r in rings.skip(1)) ForestPolygonRing.fromGeoJson(r as List),
        ],
      );
}

/// A named geographic boundary (currently just Ocala National Forest) stored
/// as real, authoritative polygon geometry — never a circle or bounding box.
/// Stored separately from `county_boundaries`/`park_boundaries`/`locations`
/// in its own `forest_boundaries` table (migration 0048), keeping this
/// experiment's data fully isolated from existing Marion County content.
class ForestBoundary implements Model {
  const ForestBoundary({
    required this.id,
    required this.name,
    required this.parts,
    this.source,
    this.sourceUrl,
    this.acres,
  });

  @override
  final String id;
  final String name;
  final List<ForestPolygonPart> parts;

  /// Attribution — never dropped, per the spec's "preserve source
  /// attribution" requirement.
  final String? source;
  final String? sourceUrl;
  final double? acres;

  bool contains(double lat, double lng) {
    for (final part in parts) {
      if (part.contains(lat, lng)) return true;
    }
    return false;
  }

  factory ForestBoundary.fromJson(Json json) {
    final polygon = json['polygon'] as List<dynamic>? ?? const [];
    return ForestBoundary(
      id: json['id']?.toString() ?? '',
      name: (json['name'] ?? '') as String,
      parts: [for (final part in polygon) ForestPolygonPart.fromGeoJson(part as List)],
      source: json['source'] as String?,
      sourceUrl: json['source_url'] as String?,
      acres: (json['acres'] as num?)?.toDouble(),
    );
  }
}
