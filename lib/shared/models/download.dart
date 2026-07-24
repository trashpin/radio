import 'package:explorer_os_mobile/core/data/model.dart';
import 'package:explorer_os_mobile/shared/models/user_favorite.dart' show FavoriteEntityType;

/// Lifecycle state of an offline download.
enum DownloadStatus {
  queued,
  downloading,
  completed,
  failed;

  static DownloadStatus fromToken(String? token) =>
      DownloadStatus.values.firstWhere(
        (s) => s.name == token,
        orElse: () => DownloadStatus.queued,
      );
}

/// A record describing an offline download of a content entity.
///
/// USER-OWNED and writable (provides [toJson] for sync/persistence). Reuses
/// [FavoriteEntityType] to identify WHAT is downloaded, so the same polymorphic
/// scheme covers favorites and downloads. `localPath`/`progress`/`sizeBytes`
/// support the future download manager UI and offline playback.
class Download implements Model {
  const Download({
    required this.id,
    required this.entityType,
    required this.entityId,
    this.status = DownloadStatus.queued,
    this.progress = 0,
    this.sizeBytes,
    this.localPath,
  });

  @override
  final String id;
  final FavoriteEntityType entityType;
  final String entityId;
  final DownloadStatus status;

  /// 0..1 completion fraction.
  final double progress;
  final int? sizeBytes;
  final String? localPath;

  bool get isComplete => status == DownloadStatus.completed;

  factory Download.fromJson(Json json) => Download(
        id: json['id']?.toString() ?? '',
        entityType: FavoriteEntityType.fromToken(json['entity_type'] as String?),
        entityId: json['entity_id']?.toString() ?? '',
        status: DownloadStatus.fromToken(json['status'] as String?),
        progress: (json['progress'] as num?)?.toDouble() ?? 0,
        sizeBytes: (json['size_bytes'] as num?)?.toInt(),
        localPath: json['local_path'] as String?,
      );

  Json toJson() => {
        'id': id,
        'entity_type': entityType.token,
        'entity_id': entityId,
        'status': status.name,
        'progress': progress,
        if (sizeBytes != null) 'size_bytes': sizeBytes,
        if (localPath != null) 'local_path': localPath,
      };
}
