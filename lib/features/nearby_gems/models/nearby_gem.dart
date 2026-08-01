/// An admin-curated Nearby Gem — the ONLY source of Nearby Gems shown to users.
/// Nothing here is auto-imported from Google Places or any third party.
class NearbyGem {
  const NearbyGem({
    required this.id,
    required this.name,
    this.category,
    this.badge,
    this.featuredImage,
    this.galleryImages = const [],
    this.latitude,
    this.longitude,
    this.address,
    this.website,
    this.phone,
    this.narrationUrl,
    this.narrationScript,
    this.shortDescription,
    this.longStory,
    this.active = true,
    this.featured = false,
    this.priority = 0,
    this.popularity = 0,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String? category;

  /// e.g. "Local Favorite", "ExplorerOS Pick", "Worth the Drive", "Hidden Gem".
  final String? badge;
  final String? featuredImage;
  final List<String> galleryImages;
  final double? latitude;
  final double? longitude;
  final String? address;
  final String? website;
  final String? phone;

  /// AI narration audio URL ("Hear Story") — played first when present.
  final String? narrationUrl;

  /// The exact spoken script fed to ElevenLabs (admin "Generate Narration") or
  /// spoken on-device when no [narrationUrl] exists yet.
  final String? narrationScript;

  /// One-line description shown on cards.
  final String? shortDescription;

  /// The Long Description — rich detail, and the last-resort narration text.
  final String? longStory;
  final bool active;

  /// Editorial "featured" flag — featured gems surface first in discovery.
  final bool featured;

  /// Editorial priority (higher = surfaced sooner). Admin-controlled.
  final int priority;

  /// Popularity signal (e.g. play/visit count) — higher surfaces sooner.
  final int popularity;
  final DateTime? updatedAt;

  bool get hasCoordinates =>
      latitude != null &&
      longitude != null &&
      !(latitude == 0 && longitude == 0);

  /// Whether a prerecorded/generated narration audio file exists.
  bool get hasAudio => (narrationUrl ?? '').trim().isNotEmpty;

  /// Back-compat alias — a gem "has a story" once it can be narrated (audio,
  /// script, or a Long Description to speak).
  bool get hasStory => canNarrate;

  /// The narration text used when no audio exists: the dedicated script first,
  /// then the Long Description, then the short description (never empty-string).
  String? get narrationText {
    for (final s in [narrationScript, longStory, shortDescription]) {
      final t = (s ?? '').trim();
      if (t.isNotEmpty) return t;
    }
    return null;
  }

  /// Whether this gem can be narrated at all (prerecorded audio OR any text we
  /// can speak on-device).
  bool get canNarrate => hasAudio || narrationText != null;

  /// Badge options offered in the admin editor.
  static const List<String> badgeOptions = [
    'Local Favorite',
    'ExplorerOS Pick',
    'Worth the Drive',
    'Hidden Gem',
    'Family Friendly',
    'Must See',
  ];

  /// Category options offered in the admin editor.
  static const List<String> categoryOptions = [
    'Restaurant',
    'Coffee',
    'Ice Cream',
    'Bakery',
    'Dessert',
    'Bar',
    'Shopping',
    'Attraction',
    'Museum',
    'Lodging',
    'Outdoors',
    'Other',
  ];

  static double? _d(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
  static List<String> _strs(dynamic v) => v is List
      ? v.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList()
      : const [];

  factory NearbyGem.fromJson(Map<String, dynamic> j) => NearbyGem(
    id: (j['id'] ?? '').toString(),
    name: (j['name'] ?? '') as String,
    category: j['category'] as String?,
    badge: j['badge'] as String?,
    featuredImage: j['featured_image'] as String?,
    galleryImages: _strs(j['gallery_images']),
    latitude: _d(j['latitude']),
    longitude: _d(j['longitude']),
    address: j['address'] as String?,
    website: j['website'] as String?,
    phone: j['phone'] as String?,
    narrationUrl: j['narration_url'] as String?,
    narrationScript: j['narration_script'] as String?,
    shortDescription: j['short_description'] as String?,
    longStory: j['long_story'] as String?,
    active: (j['active'] ?? true) as bool,
    featured: (j['featured'] ?? false) as bool,
    priority: (j['priority'] as num?)?.toInt() ?? 0,
    popularity: (j['popularity'] as num?)?.toInt() ?? 0,
    updatedAt: DateTime.tryParse('${j['updated_at']}'),
  );

  /// Column map for insert/update (id/timestamps managed by the DB).
  Map<String, dynamic> toWrite() => {
    'name': name,
    'category': category,
    'badge': badge,
    'featured_image': featuredImage,
    'gallery_images': galleryImages,
    'latitude': latitude,
    'longitude': longitude,
    'address': address,
    'website': website,
    'phone': phone,
    'narration_url': narrationUrl,
    'narration_script': narrationScript,
    'short_description': shortDescription,
    'long_story': longStory,
    'active': active,
    'featured': featured,
    'priority': priority,
    'popularity': popularity,
  };
}
