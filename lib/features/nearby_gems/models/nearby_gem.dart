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
    this.shortDescription,
    this.longStory,
    this.active = true,
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

  /// AI narration audio URL ("Hear Story").
  final String? narrationUrl;
  final String? shortDescription;
  final String? longStory;
  final bool active;
  final DateTime? updatedAt;

  bool get hasCoordinates =>
      latitude != null &&
      longitude != null &&
      !(latitude == 0 && longitude == 0);
  bool get hasStory => (narrationUrl ?? '').trim().isNotEmpty;

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
        shortDescription: j['short_description'] as String?,
        longStory: j['long_story'] as String?,
        active: (j['active'] ?? true) as bool,
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
        'short_description': shortDescription,
        'long_story': longStory,
        'active': active,
      };
}
