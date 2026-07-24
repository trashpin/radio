/// A read-only representation of an ExplorerOS destination.
///
/// Destinations (National Park Buddy, Florida Buddy, Historic Route 66, and any
/// future ones) are NEVER hardcoded. This model simply describes the shape of a
/// destination record returned by the backend (Supabase) so the UI has a
/// type-safe object to render. It is immutable and only knows how to be created
/// *from* backend JSON — reflecting the read-only nature of the mobile client.
class Destination {
  const Destination({
    required this.id,
    required this.name,
    this.description,
    this.imageUrl,
  });

  final String id;
  final String name;
  final String? description;
  final String? imageUrl;

  /// Builds a [Destination] from a backend JSON map. Missing/renamed keys are
  /// handled defensively so one malformed row cannot crash the app.
  factory Destination.fromJson(Map<String, dynamic> json) {
    return Destination(
      id: json['id']?.toString() ?? '',
      name: (json['name'] ?? '') as String,
      description: json['description'] as String?,
      imageUrl: json['image_url'] as String?,
    );
  }
}
