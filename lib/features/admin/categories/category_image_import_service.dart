import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/admin/media_search/logic/image_ranking.dart';
import 'package:explorer_os_mobile/features/admin/media_search/models/image_search_result.dart';
import 'package:explorer_os_mobile/shared/design/category_fallback_image_repository.dart';

/// Downloads, resizes, re-hosts, records (with full attribution), and
/// assigns an open-license image as a category-visual bucket's fallback
/// photograph — the same Wikimedia/Openverse pipeline
/// [EventImageImportService]/`ImageImportService` already run, applied to
/// `category_fallback_images` instead of an individual event/location's own
/// `image_url`. A category has no destination row of its own (its `id` is
/// just a canonical string key, see `category_visuals.dart`), so this stays
/// its own small class rather than forcing that shape onto the others.
class CategoryImageImportService {
  CategoryImageImportService(this._repo, {http.Client? client})
      : _client = client ?? http.Client();

  final CategoryFallbackImageRepository _repo;
  final http.Client _client;

  static const String bucket = 'media';

  static String _slug(String s) {
    final base = s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return base.isEmpty ? 'image' : base;
  }

  Future<String> _upload(String path, Uint8List bytes, String contentType) async {
    final client = SupabaseService.client;
    await client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );
    return client.storage.from(bucket).getPublicUrl(path);
  }

  Future<String> import(
    ImageSearchResult result,
    String categoryKey, {
    int minWidth = kMinImageWidth,
  }) async {
    final folder = 'categories/${_slug(categoryKey)}';
    final base = '${_slug(result.title)}_${DateTime.now().millisecondsSinceEpoch}';

    String heroUrl;
    int? width = result.width;
    int? height = result.height;
    int? fileSize = result.fileSize;
    String? storagePath;

    Uint8List? bytes;
    try {
      final res = await _client.get(Uri.parse(result.imageUrl));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        bytes = res.bodyBytes;
      }
    } catch (_) {
      // CORS / network — fall back to referencing the source URL below.
    }

    if (bytes != null) {
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        width = decoded.width;
        height = decoded.height;
        if (width < minWidth) {
          throw CategoryImageImportException(
              'Image is only ${width}px wide (minimum ${minWidth}px).');
        }
        final heroBytes = decoded.width > 1600
            ? Uint8List.fromList(
                img.encodeJpg(img.copyResize(decoded, width: 1600), quality: 88))
            : bytes;
        heroUrl = await _upload('$folder/${base}_hero.jpg', heroBytes, 'image/jpeg');
        storagePath = '$folder/${base}_hero.jpg';
        fileSize = heroBytes.length;
      } else {
        heroUrl = result.imageUrl;
      }
    } else {
      heroUrl = result.imageUrl;
    }

    // Record the asset with full attribution — same table/shape the
    // location/event import paths already write, just record_type 'category'.
    await SupabaseService.client.from('media_assets').insert({
      'destination_id': categoryKey,
      'record_type': 'category',
      'media_type': 'image',
      'storage_path': ?storagePath,
      'public_url': heroUrl,
      'thumbnail': result.thumbnailUrl,
      'title': result.title,
      'photographer': result.photographer,
      'creator': result.photographer,
      'license': result.license,
      'license_url': result.licenseUrl,
      'copyright': result.photographer,
      'source': result.source.name,
      'original_url': result.imageUrl,
      'is_hero': true,
      'width': ?width,
      'height': ?height,
      'file_size': ?fileSize,
      'imported_at': DateTime.now().toUtc().toIso8601String(),
      'alt_text': result.title,
    });

    await _repo.set(categoryKey, heroUrl);
    return heroUrl;
  }
}

class CategoryImageImportException implements Exception {
  CategoryImageImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

final categoryImageImportServiceProvider = Provider<CategoryImageImportService>(
  (ref) => CategoryImageImportService(ref.watch(categoryFallbackImageRepositoryProvider)),
);
