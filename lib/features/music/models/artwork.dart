import 'package:explorer_os_mobile/core/data/model.dart';

/// Cover art for an album/track. The image bytes live in Supabase Storage; this
/// record holds the public [url] and dimensions.
class Artwork implements Model {
  const Artwork({
    required this.id,
    required this.url,
    this.width,
    this.height,
    this.storagePath,
  });

  @override
  final String id;
  final String url;
  final int? width;
  final int? height;

  /// Path within the Supabase Storage bucket (for management/deletion).
  final String? storagePath;

  factory Artwork.fromJson(Json json) => Artwork(
        id: json['id']?.toString() ?? '',
        url: (json['url'] ?? '') as String,
        width: (json['width'] as num?)?.toInt(),
        height: (json['height'] as num?)?.toInt(),
        storagePath: json['storage_path'] as String?,
      );

  Json toJson() => {
        'id': id,
        'url': url,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (storagePath != null) 'storage_path': storagePath,
      };
}
