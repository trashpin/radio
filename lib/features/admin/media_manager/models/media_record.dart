import 'package:explorer_os_mobile/features/admin/media_manager/models/media_asset.dart';

/// A normalized content record (from `species`, `map_locations`,
/// `destinations`, …) that media can be attached to. This is what the auditor
/// scans and the Media Library lists.
class MediaRecord {
  const MediaRecord({
    required this.id,
    required this.type,
    required this.title,
    this.category,
    this.destinationId,
    this.heroImageUrl,
    this.audioUrl,
    this.altText,
    this.copyright,
    this.credits,
    this.updatedAt,
  });

  final String id;
  final MediaRecordType type;
  final String title;

  /// The raw category token from the source table.
  final String? category;
  final String? destinationId;

  /// Hero image carried on the record's own row (e.g. `species.hero_image`).
  final String? heroImageUrl;

  /// Audio carried on the record's own row (e.g. `map_locations.audio_url`).
  final String? audioUrl;

  final String? altText;
  final String? copyright;
  final String? credits;
  final DateTime? updatedAt;

  /// A stable key used to group [MediaAsset]s to their owning record.
  String get key => '${type.name}|$id';
}
