import 'package:explorer_os_mobile/core/data/model.dart';
import 'package:explorer_os_mobile/shared/models/song.dart';

/// A read-only row from Base44's `media` table (audio, photo, or video).
///
/// This is the real source of Explorer Radio audio: audio rows carry a
/// [fileUrl] that points at a file in the public `mp3` Storage bucket (or an
/// absolute URL). The mobile app is read-only for content, so this model only
/// knows how to be built *from* backend JSON.
class MediaItem implements Model {
  const MediaItem({
    required this.id,
    required this.mediaType,
    this.destinationId,
    this.stopId,
    this.speciesId,
    this.title,
    this.fileUrl,
    this.thumbnailUrl,
    this.isFeatured = false,
    this.sortOrder,
    this.published = true,
  });

  @override
  final String id;

  /// Base44 `media_type` (e.g. `audio`, `photo`, `video`).
  final String mediaType;
  final String? destinationId;
  final String? stopId;

  /// Links this media to a `species` row (e.g. narration audio for a plant).
  final String? speciesId;
  final String? title;

  /// Playable/loadable source. Absolute URL, or a storage path resolved against
  /// the `mp3` bucket by [SupabaseMediaUrl].
  final String? fileUrl;
  final String? thumbnailUrl;
  final bool isFeatured;
  final int? sortOrder;
  final bool published;

  /// True when this row is playable audio. Detects both an explicit
  /// `media_type` of `audio` and common audio file extensions (defensive, since
  /// Base44 `media_type` values aren't strictly enumerated).
  bool get isAudio {
    if (mediaType.toLowerCase().contains('audio')) return true;
    final url = fileUrl?.toLowerCase() ?? '';
    return url.endsWith('.mp3') ||
        url.endsWith('.m4a') ||
        url.endsWith('.aac') ||
        url.endsWith('.wav');
  }

  factory MediaItem.fromJson(Json json) => MediaItem(
        id: (json['media_id'] ?? json['id'])?.toString() ?? '',
        mediaType: (json['media_type'] ?? '') as String,
        destinationId: json['destination_id']?.toString(),
        stopId: json['stop_id']?.toString(),
        speciesId: json['species_id']?.toString(),
        title: json['title'] as String?,
        fileUrl: (json['file_url'] ?? json['url']) as String?,
        thumbnailUrl: json['thumbnail_url'] as String?,
        isFeatured: (json['is_featured'] ?? false) as bool,
        sortOrder: (json['sort_order'] as num?)?.toInt(),
        published: (json['published'] ?? true) as bool,
      );

  /// Maps an audio media row to a [Song] so the Radio Engine (which consumes
  /// [Song]s) needs no changes. [stationId] scopes the song to its station
  /// (a destination). [resolvedUrl] is the playable URL after bucket resolution.
  Song toSong(String stationId, {String? resolvedUrl}) => Song(
        id: id,
        stationId: stationId,
        title: title ?? 'Untitled',
        audioUrl: resolvedUrl ?? fileUrl,
      );
}
