import 'package:explorer_os_mobile/core/data/model.dart';

/// A row in the master `species` catalog — any natural-history subject
/// (plant, tree, bird, mammal, waterfall, historic site, …).
///
/// Read/write content. Image/audio/video assets live in `media` (linked via
/// `media.species_id` or `hero_media_id`); `heroImage` may hold a direct URL.
class Species implements Model {
  const Species({
    required this.id,
    required this.category,
    required this.commonName,
    this.scientificName,
    this.pronunciation,
    this.description,
    this.size,
    this.weight,
    this.color,
    this.shape,
    this.specialMarkings,
    this.maleVsFemale,
    this.juvenileNotes,
    this.diet,
    this.behavior,
    this.lifeSpan,
    this.breeding,
    this.conservationStatus,
    this.safetyInfo,
    this.funFacts,
    this.heroImage,
    this.heroMediaId,
    this.destinationId,
    this.featured = false,
    this.published = true,
    this.sortOrder,
  });

  @override
  final String id;
  final String category;
  final String commonName;
  final String? scientificName;
  final String? pronunciation;
  final String? description;
  final String? size;
  final String? weight;
  final String? color;
  final String? shape;
  final String? specialMarkings;
  final String? maleVsFemale;
  final String? juvenileNotes;
  final String? diet;
  final String? behavior;
  final String? lifeSpan;
  final String? breeding;
  final String? conservationStatus;
  final String? safetyInfo;
  final String? funFacts;

  /// Thumbnail URL — direct `hero_image`, or the embedded hero media file_url
  /// (folded in during parsing).
  final String? heroImage;
  final String? heroMediaId;
  final String? destinationId;
  final bool featured;
  final bool published;
  final int? sortOrder;

  String? get heroImageUrl =>
      (heroImage != null && heroImage!.isNotEmpty) ? heroImage : null;

  factory Species.fromJson(Json json) {
    // Support PostgREST embed: select=*,hero:media!hero_media_id(file_url)
    String? embedded;
    final hero = json['hero'];
    if (hero is Map && hero['file_url'] is String) {
      embedded = hero['file_url'] as String;
    }
    return Species(
      id: (json['species_id'] ?? json['id'])?.toString() ?? '',
      category: (json['category'] ?? '') as String,
      commonName: (json['common_name'] ?? json['name'] ?? '') as String,
      scientificName: json['scientific_name'] as String?,
      pronunciation: json['pronunciation'] as String?,
      description: json['description'] as String?,
      size: json['size'] as String?,
      weight: json['weight'] as String?,
      color: json['color'] as String?,
      shape: json['shape'] as String?,
      specialMarkings: json['special_markings'] as String?,
      maleVsFemale: json['male_vs_female'] as String?,
      juvenileNotes: json['juvenile_notes'] as String?,
      diet: json['diet'] as String?,
      behavior: json['behavior'] as String?,
      lifeSpan: json['life_span'] as String?,
      breeding: json['breeding'] as String?,
      conservationStatus: json['conservation_status'] as String?,
      safetyInfo: json['safety_info'] as String?,
      funFacts: json['fun_facts'] as String?,
      heroImage:
          (json['hero_image'] ?? json['image_url'] ?? embedded) as String?,
      heroMediaId: json['hero_media_id']?.toString(),
      destinationId: json['destination_id']?.toString(),
      featured: (json['featured'] ?? false) as bool,
      published: (json['published'] ?? true) as bool,
      sortOrder: (json['sort_order'] as num?)?.toInt(),
    );
  }

  /// Serializes for insert/update (omits null keys so DB defaults apply).
  Json toJson() => {
        'species_id': id,
        'category': category,
        'common_name': commonName,
        if (scientificName != null) 'scientific_name': scientificName,
        if (pronunciation != null) 'pronunciation': pronunciation,
        if (description != null) 'description': description,
        if (size != null) 'size': size,
        if (color != null) 'color': color,
        if (diet != null) 'diet': diet,
        if (behavior != null) 'behavior': behavior,
        if (conservationStatus != null)
          'conservation_status': conservationStatus,
        if (funFacts != null) 'fun_facts': funFacts,
        if (heroImage != null) 'hero_image': heroImage,
        if (heroMediaId != null) 'hero_media_id': heroMediaId,
        if (destinationId != null) 'destination_id': destinationId,
        'featured': featured,
        'published': published,
        if (sortOrder != null) 'sort_order': sortOrder,
      };
}
