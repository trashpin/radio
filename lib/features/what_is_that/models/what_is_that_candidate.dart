/// One physical thing the "What Is That?" directional search found — a real
/// `MasterLocation` that happened to fall within the cone the user was
/// pointing at. Carries only what the What Is That screen shows/acts on
/// (image, description, distance, coordinates); never invents any of it —
/// every field traces back to the underlying `locations` record or the pure
/// geometry of the search itself.
class WhatIsThatCandidate {
  const WhatIsThatCandidate({
    required this.id,
    required this.name,
    required this.locationId,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
    required this.bearingDegrees,
    this.imageUrl,
    this.description,
    this.audioUrl,
    this.typeLabel,
  });

  /// The search result's own id (`loc:<locationId>`), stable across a search.
  final String id;
  final String name;

  /// The raw `locations.id` this candidate is about — what Tell Me More and
  /// DJ Sunny narration key off of.
  final String locationId;
  final double latitude;
  final double longitude;

  /// Straight-line distance from the traveler when this search ran.
  final double distanceMeters;

  /// True bearing (0-360, from true north) from the traveler to this place.
  final double bearingDegrees;

  final String? imageUrl;
  final String? description;
  final String? audioUrl;
  final String? typeLabel;

  bool get hasAudio => (audioUrl ?? '').trim().isNotEmpty;

  /// "0.8 mi" / "3 mi" — the same rounding convention the rest of the radio
  /// UI uses for distance labels.
  String get distanceLabel {
    final miles = distanceMeters / 1609.344;
    return miles < 10
        ? '${miles.toStringAsFixed(1)} mi'
        : '${miles.round()} mi';
  }
}
