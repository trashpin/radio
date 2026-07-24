/// A read-only representation of an ExplorerOS destination.
///
/// Destinations (National Park Buddy, Florida Buddy, Historic Route 66, and any
/// future ones) are NEVER hardcoded in the app. This model simply describes the
/// shape of a destination record as it comes back from the backend (Supabase),
/// so the UI has a type-safe object to render.
///
/// The class is immutable and only knows how to be *created from* backend JSON
/// ([Destination.fromJson]) — it never writes back, reflecting the read-only
/// nature of the mobile client.
class Destination {
  const Destination({
    required this.id,
    required this.name,
    this.description,
    this.imageUrl,
  });

  /// Backend primary key (e.g. Supabase row id).
  final String id;

  /// Display name of the destination.
  final String name;

  /// Optional longer description shown on detail screens.
  final String? description;

  /// Optional hero/thumbnail image URL served by the backend.
  final String? imageUrl;

  /// Builds a [Destination] from a backend JSON map. Missing/renamed keys are
  /// handled defensively so a single malformed row cannot crash the app.
  factory Destination.fromJson(Map<String, dynamic> json) {
    return Destination(
      id: json['id']?.toString() ?? '',
      name: (json['name'] ?? '') as String,
      description: json['description'] as String?,
      imageUrl: json['image_url'] as String?,
    );
  }
}
