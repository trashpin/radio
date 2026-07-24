/// A read-only representation of an ExplorerOS destination.
///
/// Destinations (National Park Buddy, Florida Buddy, Historic Route 66, and any
/// future ones) are NEVER hardcoded. This model describes the shape of a
/// destination record returned by the backend (Supabase) so the UI has a
/// type-safe object to render. It is immutable and only knows how to be created
/// *from* backend JSON — reflecting the read-only nature of the mobile client.
///
/// All fields beyond [id]/[name] are optional so the UI degrades gracefully when
/// the backend omits them (e.g. a row without a category or image).
class Destination {
  const Destination({
    required this.id,
    required this.name,
    this.description,
    this.imageUrl,
    this.location,
    this.category,
    this.featured = false,
    this.distanceLabel,
  });

  final String id;
  final String name;
  final String? description;
  final String? imageUrl;

  /// Human-readable location line (e.g. "Ocala, Florida"), shown as a subtitle.
  final String? location;

  /// Backend category token used by the Explore filters (e.g. "park", "trail",
  /// "scenic"). See [DestinationCategory].
  final String? category;

  /// Whether this destination should be highlighted in the Featured section.
  final bool featured;

  /// Optional pre-computed distance label (e.g. "12 mi"). Supplied by the
  /// backend for now; will be computed live once the GPS feature ships.
  final String? distanceLabel;

  /// Builds a [Destination] from a backend JSON map. Missing/renamed keys are
  /// handled defensively so one malformed row cannot crash the app.
  factory Destination.fromJson(Map<String, dynamic> json) {
    return Destination(
      id: json['id']?.toString() ?? '',
      name: (json['name'] ?? '') as String,
      description: json['description'] as String?,
      imageUrl: json['image_url'] as String?,
      location: json['location'] as String?,
      category: json['category'] as String?,
      featured: (json['featured'] ?? json['is_featured'] ?? false) as bool,
      distanceLabel: json['distance_label'] as String?,
    );
  }
}
