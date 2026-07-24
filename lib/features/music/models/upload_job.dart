import 'package:explorer_os_mobile/core/data/model.dart';

/// The kind of bulk import an [UploadJob] represents.
enum UploadJobType { csv, zip, audio, artwork }

/// Lifecycle of an [UploadJob].
enum UploadJobStatus { queued, running, completed, failed }

/// Tracks progress of a bulk import (CSV/ZIP/audio) so the UI can show a
/// progress bar and the operation can be resumed/audited.
///
/// USER/ADMIN-OWNED (provides [toJson]).
class UploadJob implements Model {
  const UploadJob({
    required this.id,
    required this.type,
    this.status = UploadJobStatus.queued,
    this.totalItems = 0,
    this.processedItems = 0,
    this.error,
    this.createdAt,
  });

  @override
  final String id;
  final UploadJobType type;
  final UploadJobStatus status;
  final int totalItems;
  final int processedItems;
  final String? error;
  final DateTime? createdAt;

  double get progress => totalItems == 0 ? 0 : processedItems / totalItems;

  UploadJob copyWith({
    UploadJobStatus? status,
    int? totalItems,
    int? processedItems,
    String? error,
  }) {
    return UploadJob(
      id: id,
      type: type,
      status: status ?? this.status,
      totalItems: totalItems ?? this.totalItems,
      processedItems: processedItems ?? this.processedItems,
      error: error ?? this.error,
      createdAt: createdAt,
    );
  }

  factory UploadJob.fromJson(Json json) => UploadJob(
        id: json['id']?.toString() ?? '',
        type: UploadJobType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => UploadJobType.csv,
        ),
        status: UploadJobStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => UploadJobStatus.queued,
        ),
        totalItems: (json['total_items'] as num?)?.toInt() ?? 0,
        processedItems: (json['processed_items'] as num?)?.toInt() ?? 0,
        error: json['error'] as String?,
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      );

  Json toJson() => {
        'id': id,
        'type': type.name,
        'status': status.name,
        'total_items': totalItems,
        'processed_items': processedItems,
        if (error != null) 'error': error,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      };
}
