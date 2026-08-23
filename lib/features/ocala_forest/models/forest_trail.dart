import 'dart:convert';

import 'package:explorer_os_mobile/core/data/model.dart';

/// One point of a trail's line geometry — plain lat/lng, no dependency on
/// any particular map package (mirrors [LatLngPoint] in point_in_polygon.dart,
/// but a trail's geometry is display-only here, never fed through the
/// ray-casting point-in-polygon check that geometry is used for).
typedef ForestTrailPoint = ({double lat, double lng});

/// A real, official trail record imported from the U.S. Forest Service's
/// National Forest System Trails dataset (spec: "Import Official Ocala
/// National Forest Trail Records") — grouped from one or more raw GIS
/// segments sharing the same official `trailNo` (see
/// `forest_trail_segments`/`forest_trails`/`rebuild_forest_trails` in
/// migration 0050_ocala_forest_trails.sql).
///
/// Every field is either a literal USFS-provided value, a real aggregate of
/// USFS-provided numbers ([lengthMiles]), or a geometric fact of the USFS
/// geometry itself ([geometricStartLat]/[geometricStartLng] — explicitly
/// NOT an official trailhead facility, since the source has no trailhead
/// layer). A field the source didn't provide is left null here, never
/// invented client-side either.
class ForestTrail implements Model {
  const ForestTrail({
    required this.id,
    required this.forestId,
    required this.trailNo,
    this.trailName,
    this.trailType,
    this.trailClass,
    this.trailSurface,
    this.accessibilityStatus,
    this.nationalTrailDesignation,
    this.managingOrg,
    this.lengthMiles,
    this.segmentCount = 0,
    this.parts = const [],
    this.geometricStartLat,
    this.geometricStartLng,
    this.source,
    this.sourceDataset,
    this.sourceUrl,
    this.mapImageUrl,
    this.mapSourceName,
    this.mapSourceUrl,
    this.mapRetrievedAt,
    this.mapDocumentId,
    this.audioScript,
    this.audioVoiceId,
    this.audioUrl,
    this.audioDurationSeconds,
    this.audioGeneratedAt,
    this.audioStatus = 'none',
  });

  @override
  final String id;
  final String forestId;

  /// The USFS official trail number (e.g. "0520") — never invented; this is
  /// the field the source itself uses to identify a distinct trail.
  final String trailNo;
  final String? trailName;
  final String? trailType;
  final String? trailClass;
  final String? trailSurface;
  final String? accessibilityStatus;
  final int? nationalTrailDesignation;
  final String? managingOrg;

  /// Sum of each segment's official `gis_miles`; null if none of this
  /// trail's segments carried a mileage value.
  final double? lengthMiles;
  final int segmentCount;

  /// The real trail line geometry, one list of points per line part of the
  /// source's MultiLineString — never reduced to a single marker point.
  final List<List<ForestTrailPoint>> parts;

  /// The trail geometry's own first coordinate — a derived geometric fact,
  /// NOT an official trailhead facility record (the source publishes no
  /// trailhead layer). Always label this as such in the UI.
  final double? geometricStartLat;
  final double? geometricStartLng;

  final String? source;
  final String? sourceDataset;
  final String? sourceUrl;

  /// An official printable/scannable trail map, if one has ever been
  /// sourced and attached (spec: "actual physical trail map") — null for
  /// every trail today (see migration 0052's own doc comment: USFS
  /// publishes no per-trail map for Ocala, only whole-forest products).
  /// When null, the UI falls back to the real imported [parts] geometry.
  final String? mapImageUrl;
  final String? mapSourceName;
  final String? mapSourceUrl;
  final DateTime? mapRetrievedAt;
  final String? mapDocumentId;

  /// The ElevenLabs trail-audio introduction (spec: "Trail Audio Tour").
  final String? audioScript;
  final String? audioVoiceId;
  final String? audioUrl;
  final double? audioDurationSeconds;
  final DateTime? audioGeneratedAt;

  /// none | pending | generating | ready | error.
  final String audioStatus;

  bool get hasGeometricStart => geometricStartLat != null && geometricStartLng != null;
  bool get hasOfficialMap => (mapImageUrl ?? '').trim().isNotEmpty;
  bool get hasReadyAudio => audioStatus == 'ready' && (audioUrl ?? '').trim().isNotEmpty;

  ForestTrail copyWithAudio({
    String? audioScript,
    String? audioVoiceId,
    String? audioUrl,
    double? audioDurationSeconds,
    DateTime? audioGeneratedAt,
    String? audioStatus,
  }) =>
      ForestTrail(
        id: id,
        forestId: forestId,
        trailNo: trailNo,
        trailName: trailName,
        trailType: trailType,
        trailClass: trailClass,
        trailSurface: trailSurface,
        accessibilityStatus: accessibilityStatus,
        nationalTrailDesignation: nationalTrailDesignation,
        managingOrg: managingOrg,
        lengthMiles: lengthMiles,
        segmentCount: segmentCount,
        parts: parts,
        geometricStartLat: geometricStartLat,
        geometricStartLng: geometricStartLng,
        source: source,
        sourceDataset: sourceDataset,
        sourceUrl: sourceUrl,
        mapImageUrl: mapImageUrl,
        mapSourceName: mapSourceName,
        mapSourceUrl: mapSourceUrl,
        mapRetrievedAt: mapRetrievedAt,
        mapDocumentId: mapDocumentId,
        audioScript: audioScript ?? this.audioScript,
        audioVoiceId: audioVoiceId ?? this.audioVoiceId,
        audioUrl: audioUrl ?? this.audioUrl,
        audioDurationSeconds: audioDurationSeconds ?? this.audioDurationSeconds,
        audioGeneratedAt: audioGeneratedAt ?? this.audioGeneratedAt,
        audioStatus: audioStatus ?? this.audioStatus,
      );

  static List<List<ForestTrailPoint>> _partsFromGeoJson(String? geoJson) {
    if (geoJson == null || geoJson.isEmpty) return const [];
    try {
      final decoded = jsonDecode(geoJson) as Map<String, dynamic>;
      final coords = decoded['coordinates'] as List<dynamic>? ?? const [];
      return [
        for (final part in coords)
          [
            for (final pt in part as List<dynamic>)
              (lat: (pt[1] as num).toDouble(), lng: (pt[0] as num).toDouble()),
          ],
      ];
    } catch (_) {
      // A malformed geom_geojson value is a data problem to surface, not to
      // crash the whole trail list over — the trail still displays with no
      // line geometry rather than taking every other trail down with it.
      return const [];
    }
  }

  factory ForestTrail.fromJson(Json json) => ForestTrail(
        id: json['id']?.toString() ?? '',
        forestId: json['forest_id']?.toString() ?? '',
        trailNo: (json['trail_no'] ?? '') as String,
        trailName: json['trail_name'] as String?,
        trailType: json['trail_type'] as String?,
        trailClass: json['trail_class'] as String?,
        trailSurface: json['trail_surface'] as String?,
        accessibilityStatus: json['accessibility_status'] as String?,
        nationalTrailDesignation: (json['national_trail_designation'] as num?)?.toInt(),
        managingOrg: json['managing_org'] as String?,
        lengthMiles: (json['length_miles'] as num?)?.toDouble(),
        segmentCount: (json['segment_count'] as num?)?.toInt() ?? 0,
        parts: _partsFromGeoJson(json['geom_geojson'] as String?),
        geometricStartLat: (json['geometric_start_lat'] as num?)?.toDouble(),
        geometricStartLng: (json['geometric_start_lng'] as num?)?.toDouble(),
        source: json['source'] as String?,
        sourceDataset: json['source_dataset'] as String?,
        sourceUrl: json['source_url'] as String?,
        mapImageUrl: json['map_image_url'] as String?,
        mapSourceName: json['map_source_name'] as String?,
        mapSourceUrl: json['map_source_url'] as String?,
        mapRetrievedAt: DateTime.tryParse(json['map_retrieved_at']?.toString() ?? ''),
        mapDocumentId: json['map_document_id'] as String?,
        audioScript: json['audio_script'] as String?,
        audioVoiceId: json['audio_voice_id'] as String?,
        audioUrl: json['audio_url'] as String?,
        audioDurationSeconds: (json['audio_duration_seconds'] as num?)?.toDouble(),
        audioGeneratedAt: DateTime.tryParse(json['audio_generated_at']?.toString() ?? ''),
        audioStatus: (json['audio_status'] as String?) ?? 'none',
      );
}
