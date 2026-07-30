import 'package:explorer_os_mobile/core/data/model.dart';

/// The kind of a media asset.
enum MediaType {
  image,
  video,
  audio,
  ambient,
  narration,
  document;

  static MediaType fromString(String? s) {
    switch ((s ?? 'image').toLowerCase()) {
      case 'video':
        return MediaType.video;
      case 'audio':
        return MediaType.audio;
      case 'ambient':
        return MediaType.ambient;
      case 'narration':
        return MediaType.narration;
      case 'document':
      case 'pdf':
        return MediaType.document;
      default:
        return MediaType.image;
    }
  }

  String get label => switch (this) {
        MediaType.image => 'Image',
        MediaType.video => 'Video',
        MediaType.audio => 'Audio',
        MediaType.ambient => 'Ambient',
        MediaType.narration => 'Narration',
        MediaType.document => 'Document',
      };
}

/// The ExplorerOS content categories a record can belong to. Each maps to a
/// Storage folder for uploaded media.
enum MediaRecordType {
  animals('animals'),
  birds('birds'),
  reptiles('reptiles'),
  amphibians('amphibians'),
  fish('fish'),
  plants('plants'),
  trees('trees'),
  wildflowers('flowers'),
  rivers('rivers'),
  springs('springs'),
  trails('trails'),
  campgrounds('campgrounds'),
  scenicDrives('scenic_drives'),
  historicSites('historic_sites'),
  visitorCenters('visitor_centers'),
  waterfalls('waterfalls'),
  landmarks('landmarks'),
  other('other');

  const MediaRecordType(this.folder);

  /// The Supabase Storage folder that media for this category is uploaded into.
  final String folder;

  String get label => switch (this) {
        MediaRecordType.animals => 'Animals',
        MediaRecordType.birds => 'Birds',
        MediaRecordType.reptiles => 'Reptiles',
        MediaRecordType.amphibians => 'Amphibians',
        MediaRecordType.fish => 'Fish',
        MediaRecordType.plants => 'Plants',
        MediaRecordType.trees => 'Trees',
        MediaRecordType.wildflowers => 'Wildflowers',
        MediaRecordType.rivers => 'Rivers',
        MediaRecordType.springs => 'Springs',
        MediaRecordType.trails => 'Trails',
        MediaRecordType.campgrounds => 'Campgrounds',
        MediaRecordType.scenicDrives => 'Scenic Drives',
        MediaRecordType.historicSites => 'Historic Sites',
        MediaRecordType.visitorCenters => 'Visitor Centers',
        MediaRecordType.waterfalls => 'Waterfalls',
        MediaRecordType.landmarks => 'Landmarks',
        MediaRecordType.other => 'Other',
      };

  /// Maps a free-form category token (from `species.category`,
  /// `map_locations.category`, etc.) to a normalized [MediaRecordType].
  static MediaRecordType fromToken(String? token) {
    final t = (token ?? '').toLowerCase();
    if (t.contains('bird')) return MediaRecordType.birds;
    if (t.contains('reptile')) return MediaRecordType.reptiles;
    if (t.contains('amphib')) return MediaRecordType.amphibians;
    if (t.contains('fish')) return MediaRecordType.fish;
    if (t.contains('tree')) return MediaRecordType.trees;
    if (t.contains('wildflower') || t.contains('flower')) {
      return MediaRecordType.wildflowers;
    }
    if (t.contains('plant')) return MediaRecordType.plants;
    if (t.contains('mammal') || t.contains('animal') || t.contains('wildlife')) {
      return MediaRecordType.animals;
    }
    if (t.contains('waterfall')) return MediaRecordType.waterfalls;
    if (t.contains('spring')) return MediaRecordType.springs;
    if (t.contains('river') || t.contains('water')) return MediaRecordType.rivers;
    if (t.contains('trail')) return MediaRecordType.trails;
    if (t.contains('camp')) return MediaRecordType.campgrounds;
    if (t.contains('scenic') || t.contains('drive') || t.contains('overlook')) {
      return MediaRecordType.scenicDrives;
    }
    if (t.contains('historic')) return MediaRecordType.historicSites;
    if (t.contains('visitor')) return MediaRecordType.visitorCenters;
    if (t.contains('landmark')) return MediaRecordType.landmarks;
    return MediaRecordType.other;
  }
}

/// A single media asset row (`media_assets` table).
class MediaAsset implements Model {
  const MediaAsset({
    required this.id,
    this.recordId,
    this.recordType,
    this.destinationId,
    this.mediaType = MediaType.image,
    this.storagePath,
    this.publicUrl,
    this.thumbnail,
    this.title,
    this.caption,
    this.photographer,
    this.copyright,
    this.license,
    this.altText,
    this.tags = const [],
    this.width,
    this.height,
    this.fileSize,
    this.isHero = false,
    this.source,
    this.originalUrl,
    this.mediumUrl,
    this.createdAt,
    this.updatedAt,
  });

  @override
  final String id;
  final String? recordId;
  final String? recordType;
  final String? destinationId;
  final MediaType mediaType;
  final String? storagePath;
  final String? publicUrl;
  final String? thumbnail;
  final String? title;
  final String? caption;
  final String? photographer;
  final String? copyright;
  final String? license;
  final String? altText;
  final List<String> tags;
  final int? width;
  final int? height;
  final int? fileSize;
  final bool isHero;

  /// Open-license provider this image came from ('openverse'|'wikimedia'|'upload').
  final String? source;

  /// The provider's original image URL (attribution / re-fetch).
  final String? originalUrl;

  /// A medium (≈1200px) working copy URL, when generated on import.
  final String? mediumUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isImage =>
      mediaType == MediaType.image;
  bool get isAudioLike =>
      mediaType == MediaType.audio ||
      mediaType == MediaType.ambient ||
      mediaType == MediaType.narration;

  factory MediaAsset.fromJson(Json j) => MediaAsset(
        id: (j['id'] ?? '').toString(),
        recordId: j['record_id']?.toString(),
        recordType: j['record_type'] as String?,
        destinationId: j['destination_id']?.toString(),
        mediaType: MediaType.fromString(j['media_type'] as String?),
        storagePath: j['storage_path'] as String?,
        publicUrl: j['public_url'] as String?,
        thumbnail: j['thumbnail'] as String?,
        title: j['title'] as String?,
        caption: j['caption'] as String?,
        photographer: j['photographer'] as String?,
        copyright: j['copyright'] as String?,
        license: j['license'] as String?,
        altText: j['alt_text'] as String?,
        tags: (j['tags'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        width: (j['width'] as num?)?.toInt(),
        height: (j['height'] as num?)?.toInt(),
        fileSize: (j['file_size'] as num?)?.toInt(),
        isHero: (j['is_hero'] ?? false) as bool,
        source: j['source'] as String?,
        originalUrl: j['original_url'] as String?,
        mediumUrl: j['medium_url'] as String?,
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? ''),
        updatedAt: DateTime.tryParse(j['updated_at']?.toString() ?? ''),
      );

  Json toInsert() => {
        if (recordId != null) 'record_id': recordId,
        if (recordType != null) 'record_type': recordType,
        if (destinationId != null) 'destination_id': destinationId,
        'media_type': mediaType.name,
        if (storagePath != null) 'storage_path': storagePath,
        if (publicUrl != null) 'public_url': publicUrl,
        if (thumbnail != null) 'thumbnail': thumbnail,
        if (title != null) 'title': title,
        if (caption != null) 'caption': caption,
        if (photographer != null) 'photographer': photographer,
        if (copyright != null) 'copyright': copyright,
        if (license != null) 'license': license,
        if (altText != null) 'alt_text': altText,
        'tags': tags,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (fileSize != null) 'file_size': fileSize,
        'is_hero': isHero,
      };
}
