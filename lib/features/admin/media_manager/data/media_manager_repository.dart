import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/admin/media_manager/logic/media_audit.dart';
import 'package:explorer_os_mobile/features/admin/media_manager/models/media_asset.dart';
import 'package:explorer_os_mobile/features/admin/media_manager/models/media_record.dart';
import 'package:explorer_os_mobile/features/discovery/data/species_repository.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';

/// Writes for the Media Manager: uploads to the `media` Storage bucket and
/// rows in `media_assets`.
class MediaManagerRepository {
  const MediaManagerRepository();

  static const String bucket = 'media';

  /// Uploads [bytes] to `media/<folder>/<filename>` and returns the public URL.
  Future<String> upload({
    required String folder,
    required String filename,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final client = SupabaseService.client;
    final path = '$folder/$filename';
    await client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );
    return client.storage.from(bucket).getPublicUrl(path);
  }

  /// Uploads a file and records a `media_assets` row for it.
  Future<MediaAsset> uploadAndRecord({
    required String folder,
    required String filename,
    required Uint8List bytes,
    required String contentType,
    required MediaType mediaType,
    String? recordId,
    String? recordType,
    String? destinationId,
    String? title,
    bool isHero = false,
  }) async {
    final url = await upload(
      folder: folder,
      filename: filename,
      bytes: bytes,
      contentType: contentType,
    );
    final asset = MediaAsset(
      id: '',
      recordId: recordId,
      recordType: recordType,
      destinationId: destinationId,
      mediaType: mediaType,
      storagePath: '$folder/$filename',
      publicUrl: url,
      thumbnail: mediaType == MediaType.image ? url : null,
      title: title,
      fileSize: bytes.length,
      isHero: isHero,
    );
    final row = await SupabaseService.client
        .from('media_assets')
        .insert(asset.toInsert())
        .select()
        .single();
    return MediaAsset.fromJson(row);
  }

  Future<void> deleteAsset(String id) async {
    await SupabaseService.client.from('media_assets').delete().eq('id', id);
  }

  Future<void> updateAsset(String id, Map<String, dynamic> patch) async {
    await SupabaseService.client
        .from('media_assets')
        .update(patch)
        .eq('id', id);
  }
}

final mediaManagerRepositoryProvider =
    Provider<MediaManagerRepository>((ref) => const MediaManagerRepository());

/// All `media_assets` rows (empty until the table/content exist).
final mediaAssetsProvider = FutureProvider<List<MediaAsset>>((ref) async {
  if (!SupabaseService.isConfigured) return const [];
  try {
    final rows = await SupabaseService.client
        .from('media_assets')
        .select()
        .order('created_at', ascending: false) as List;
    return rows.cast<Map<String, dynamic>>().map(MediaAsset.fromJson).toList();
  } catch (_) {
    return const [];
  }
});

/// Every content record the Media Manager audits, aggregated from the rich
/// content tables (`species` + `map_locations`) and normalized to
/// [MediaRecord]s.
final mediaRecordsProvider = Provider<List<MediaRecord>>((ref) {
  final species = ref.watch(allSpeciesProvider).value ?? const [];
  final locations = ref.watch(mapLocationsProvider).value ?? const [];
  final out = <MediaRecord>[
    for (final s in species)
      MediaRecord(
        id: s.id,
        type: MediaRecordType.fromToken(s.category),
        title: s.commonName,
        category: s.category,
        destinationId: s.destinationId,
        heroImageUrl: s.heroImageUrl,
      ),
    for (final l in locations)
      MediaRecord(
        id: l.id,
        type: MediaRecordType.fromToken(l.category),
        title: l.name,
        category: l.category,
        destinationId: l.parkCode,
        heroImageUrl: (l.imageUrl ?? '').isEmpty ? null : l.imageUrl,
        audioUrl: (l.audioUrl ?? '').isEmpty ? null : l.audioUrl,
      ),
  ];
  return out;
});

/// The audit of every record combined with its media assets.
final mediaAuditProvider = Provider<List<RecordAudit>>((ref) {
  final records = ref.watch(mediaRecordsProvider);
  final assets = ref.watch(mediaAssetsProvider).value ?? const [];
  return auditRecords(records, assets);
});

/// Dashboard metrics.
final mediaDashboardProvider = Provider<MediaDashboardStats>((ref) {
  final records = ref.watch(mediaRecordsProvider);
  final assets = ref.watch(mediaAssetsProvider).value ?? const [];
  return computeDashboard(records, assets);
});
