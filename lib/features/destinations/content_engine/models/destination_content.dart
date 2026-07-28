import 'package:explorer_os_mobile/features/admin/media_manager/models/media_asset.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';
import 'package:explorer_os_mobile/features/maps/models/nearby_item.dart';

/// A resolved destination — the single anchor every piece of content links to.
///
/// The public API is keyed on [code] (`destination_code`); the other
/// identifiers are how the underlying content tables actually reference the
/// destination today (`destination_id`, `slug`/`park_code`, coordinates).
class DestinationRef {
  const DestinationRef({
    required this.code,
    required this.id,
    required this.name,
    this.slug,
    this.heroImage,
    this.latitude,
    this.longitude,
  });

  final String code;
  final String id;
  final String name;
  final String? slug;
  final String? heroImage;
  final double? latitude;
  final double? longitude;

  /// The best key to match `park_code` columns on (stories, songs,
  /// map_locations) — the slug, falling back to the code.
  String get parkKey => (slug != null && slug!.isNotEmpty) ? slug! : code;

  bool get hasCoordinates => latitude != null && longitude != null;

  factory DestinationRef.fromJson(Map<String, dynamic> j) {
    double? d(dynamic v) => (v as num?)?.toDouble();
    return DestinationRef(
      code: (j['destination_code'] ?? j['code'] ?? '').toString(),
      id: (j['destination_id'] ?? j['id'] ?? '').toString(),
      name: (j['name'] ?? '') as String,
      slug: j['slug'] as String?,
      heroImage: (j['hero_image'] ?? j['image_url']) as String?,
      latitude: d(j['latitude']),
      longitude: d(j['longitude']),
    );
  }
}

/// The media for a destination, grouped by role.
class DestinationMedia {
  const DestinationMedia({
    this.hero,
    this.gallery = const [],
    this.videos = const [],
    this.audio = const [],
  });

  /// The primary hero image (asset or synthesized from the destination row).
  final MediaAsset? hero;
  final List<MediaAsset> gallery;
  final List<MediaAsset> videos;
  final List<MediaAsset> audio;

  int get imageCount => (hero != null ? 1 : 0) + gallery.length;
  bool get isEmpty =>
      hero == null && gallery.isEmpty && videos.isEmpty && audio.isEmpty;

  static const empty = DestinationMedia();
}

/// Everything needed to present a destination — the output of
/// `loadDestinationExperience(destination_code)`.
class DestinationExperience {
  const DestinationExperience({
    required this.destination,
    this.media = DestinationMedia.empty,
    this.narration = const [],
    this.music = const [],
    this.wildlife = const [],
    this.plants = const [],
    this.stories = const [],
    this.nearby = const [],
    this.historicalEvents = const [],
  });

  final DestinationRef destination;
  final DestinationMedia media;

  /// Narration rows (`destination_narrations`) — approved + published.
  final List<Map<String, dynamic>> narration;

  /// Background music rows (`songs`).
  final List<Map<String, dynamic>> music;

  final List<Species> wildlife;
  final List<Species> plants;

  /// Story rows (`story_library`).
  final List<Map<String, dynamic>> stories;

  /// Nearby attractions & trails (`map_locations`), nearest first.
  final List<NearbyItem> nearby;

  final List<Map<String, dynamic>> historicalEvents;

  /// A not-found result for an unknown code.
  factory DestinationExperience.notFound(String code) => DestinationExperience(
        destination: DestinationRef(code: code, id: '', name: ''),
      );

  bool get isFound => destination.id.isNotEmpty;

  /// A compact summary useful for logging / debug UIs.
  Map<String, int> get counts => {
        'heroImages': media.hero != null ? 1 : 0,
        'gallery': media.gallery.length,
        'videos': media.videos.length,
        'audio': media.audio.length,
        'narration': narration.length,
        'music': music.length,
        'wildlife': wildlife.length,
        'plants': plants.length,
        'stories': stories.length,
        'nearby': nearby.length,
        'historicalEvents': historicalEvents.length,
      };
}
