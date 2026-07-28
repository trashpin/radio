import 'package:explorer_os_mobile/features/gps/models/gps_enums.dart';

/// A nearby "experience" surfaced by the Around Me system: a content record
/// (from `map_locations`) paired with everything needed to rank and describe it
/// relative to the visitor — distance, bearing, compass direction, and its
/// Explorer Score.
///
/// Pure data (no Flutter): styling/icons are resolved in the widget layer so
/// this stays unit-testable.
class Experience {
  const Experience({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
    required this.bearingDegrees,
    required this.score,
    this.subcategory,
    this.description,
    this.imageUrl,
    this.audioUrl,
    this.featured = false,
    this.visited = false,
    this.narrationPlayed = false,
  });

  final String id;
  final String name;
  final String category;
  final String? subcategory;
  final String? description;
  final String? imageUrl;
  final String? audioUrl;
  final double latitude;
  final double longitude;
  final bool featured;

  /// Distance from the visitor, meters.
  final double distanceMeters;

  /// Bearing from the visitor to this experience (0–360°, 0 = north).
  final double bearingDegrees;

  /// The Explorer Score used to sort (higher = show first).
  final double score;

  final bool visited;
  final bool narrationPlayed;

  bool get hasNarration => (audioUrl ?? '').isNotEmpty;

  /// The eight-point compass direction from the visitor to this experience.
  CardinalDirection get direction =>
      CardinalDirection.fromBearing(bearingDegrees);

  /// Whether this experience is a trail (used for trail-specific GPS events).
  bool get isTrail {
    final c = category.toLowerCase();
    return c.contains('trail');
  }

  Experience copyWith({
    double? distanceMeters,
    double? bearingDegrees,
    double? score,
    bool? visited,
    bool? narrationPlayed,
  }) {
    return Experience(
      id: id,
      name: name,
      category: category,
      subcategory: subcategory,
      description: description,
      imageUrl: imageUrl,
      audioUrl: audioUrl,
      latitude: latitude,
      longitude: longitude,
      featured: featured,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      bearingDegrees: bearingDegrees ?? this.bearingDegrees,
      score: score ?? this.score,
      visited: visited ?? this.visited,
      narrationPlayed: narrationPlayed ?? this.narrationPlayed,
    );
  }
}

/// Short label for a compass direction, e.g. "NE".
String cardinalShort(CardinalDirection d) => switch (d) {
      CardinalDirection.north => 'N',
      CardinalDirection.northEast => 'NE',
      CardinalDirection.east => 'E',
      CardinalDirection.southEast => 'SE',
      CardinalDirection.south => 'S',
      CardinalDirection.southWest => 'SW',
      CardinalDirection.west => 'W',
      CardinalDirection.northWest => 'NW',
    };
