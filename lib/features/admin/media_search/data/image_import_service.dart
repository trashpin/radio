import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/admin/media_search/logic/image_ranking.dart';
import 'package:explorer_os_mobile/features/admin/media_search/models/image_search_result.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

/// The result of importing one image.
class ImportResult {
  const ImportResult({
    required this.heroUrl,
    required this.thumbnailUrl,
    this.mediumUrl,
    required this.rehosted,
    required this.assetId,
    this.width,
    this.height,
  });

  /// The full-size URL now used by the app (a re-hosted Storage URL, or the
  /// original remote URL when byte download was blocked by CORS).
  final String heroUrl;
  final String thumbnailUrl;
  final String? mediumUrl;

  /// True when we downloaded + re-hosted the bytes in Supabase Storage; false
  /// when we fell back to referencing the source URL directly.
  final bool rehosted;
  final String assetId;
  final int? width;
  final int? height;
}

/// Downloads, quality-checks, resizes, re-hosts, records, and assigns an
/// open-license image to a destination — the heart of the Media Search Center.
class ImageImportService {
  ImageImportService(this._locations, {http.Client? client})
      : _client = client ?? http.Client();

  final LocationRepository _locations;
  final http.Client _client;

  static const String bucket = 'media';

  static String _slug(String s) {
    final base = s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return base.isEmpty ? 'image' : base;
  }

  String _folderFor(MasterLocation d) {
    final code = (d.destinationCode ?? '').trim();
    return code.isEmpty ? 'destinations/${_slug(d.name)}' : 'destinations/$code';
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

  /// Imports [result] and attaches it to [destination].
  ///
  /// [asHero] makes it the destination's hero (position 0 of `images`);
  /// otherwise it's appended to the gallery.
  Future<ImportResult> import(
    ImageSearchResult result,
    MasterLocation destination, {
    bool asHero = true,
    int minWidth = kMinImageWidth,
  }) async {
    final folder = _folderFor(destination);
    final base = '${_slug(result.title)}_${DateTime.now().millisecondsSinceEpoch}';

    String heroUrl;
    String thumbUrl;
    String? mediumUrl;
    bool rehosted;
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
          throw ImportException(
              'Image is only ${width}px wide (minimum ${minWidth}px).');
        }
        // Hero: original bytes if reasonable, else downscale to 2000px wide.
        final heroBytes = decoded.width > 2000
            ? Uint8List.fromList(
                img.encodeJpg(img.copyResize(decoded, width: 2000), quality: 88))
            : bytes;
        final mediumBytes = Uint8List.fromList(img.encodeJpg(
            img.copyResize(decoded,
                width: decoded.width < 1200 ? decoded.width : 1200),
            quality: 85));
        final thumbBytes = Uint8List.fromList(img.encodeJpg(
            img.copyResize(decoded,
                width: decoded.width < 400 ? decoded.width : 400),
            quality: 80));

        heroUrl = await _upload('$folder/${base}_hero.jpg', heroBytes, 'image/jpeg');
        mediumUrl =
            await _upload('$folder/${base}_medium.jpg', mediumBytes, 'image/jpeg');
        thumbUrl =
            await _upload('$folder/${base}_thumb.jpg', thumbBytes, 'image/jpeg');
        storagePath = '$folder/${base}_hero.jpg';
        fileSize = heroBytes.length;
        rehosted = true;
      } else {
        // Undecodable → treat as reference-only.
        heroUrl = result.imageUrl;
        thumbUrl = result.thumbnailUrl;
        rehosted = false;
      }
    } else {
      // Reference the source directly (attribution still fully preserved).
      heroUrl = result.imageUrl;
      thumbUrl = result.thumbnailUrl;
      rehosted = false;
    }

    // 1) Record the asset with full attribution.
    final assetRow = <String, dynamic>{
      'destination_id': destination.id,
      'record_type': destination.type.id,
      'media_type': 'image',
      'storage_path': ?storagePath,
      'public_url': heroUrl,
      'thumbnail': thumbUrl,
      'medium_url': ?mediumUrl,
      'title': result.title,
      'photographer': result.photographer,
      'creator': result.photographer,
      'license': result.license,
      'license_url': result.licenseUrl,
      'copyright': result.photographer,
      'source': result.source.name,
      'original_url': result.imageUrl,
      'is_hero': asHero,
      'width': ?width,
      'height': ?height,
      'file_size': ?fileSize,
      'imported_at': DateTime.now().toUtc().toIso8601String(),
      'alt_text': result.title,
    };
    final inserted = await SupabaseService.client
        .from('media_assets')
        .insert(assetRow)
        .select('id')
        .single();

    // 2) Assign to the destination's images (hero at position 0).
    final images = [...destination.images];
    images.removeWhere((u) => u == heroUrl);
    if (asHero) {
      images.insert(0, heroUrl);
    } else {
      images.add(heroUrl);
    }
    await _locations.update(destination.id, {'images': images});

    return ImportResult(
      heroUrl: heroUrl,
      thumbnailUrl: thumbUrl,
      mediumUrl: mediumUrl,
      rehosted: rehosted,
      assetId: (inserted['id'] ?? '').toString(),
      width: width,
      height: height,
    );
  }

  /// Imports locally-picked [bytes] (the "Upload My Own" tab). Resizes,
  /// re-hosts, records with source='upload', and assigns to [destination].
  Future<ImportResult> importBytes(
    Uint8List bytes,
    String filename,
    MasterLocation destination, {
    bool asHero = true,
    String? photographer,
    String? license,
    int minWidth = 0, // uploads are trusted; no hard floor
  }) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw ImportException('Could not read "$filename" as an image.');
    }
    if (decoded.width < minWidth) {
      throw ImportException(
          '"$filename" is only ${decoded.width}px wide (minimum ${minWidth}px).');
    }
    final folder = _folderFor(destination);
    final base =
        '${_slug(filename)}_${DateTime.now().millisecondsSinceEpoch}';
    final heroBytes = decoded.width > 2000
        ? Uint8List.fromList(
            img.encodeJpg(img.copyResize(decoded, width: 2000), quality: 88))
        : bytes;
    final mediumBytes = Uint8List.fromList(img.encodeJpg(
        img.copyResize(decoded, width: decoded.width < 1200 ? decoded.width : 1200),
        quality: 85));
    final thumbBytes = Uint8List.fromList(img.encodeJpg(
        img.copyResize(decoded, width: decoded.width < 400 ? decoded.width : 400),
        quality: 80));

    final heroUrl =
        await _upload('$folder/${base}_hero.jpg', heroBytes, 'image/jpeg');
    final mediumUrl =
        await _upload('$folder/${base}_medium.jpg', mediumBytes, 'image/jpeg');
    final thumbUrl =
        await _upload('$folder/${base}_thumb.jpg', thumbBytes, 'image/jpeg');

    final inserted = await SupabaseService.client.from('media_assets').insert({
      'destination_id': destination.id,
      'record_type': destination.type.id,
      'media_type': 'image',
      'storage_path': '$folder/${base}_hero.jpg',
      'public_url': heroUrl,
      'thumbnail': thumbUrl,
      'medium_url': mediumUrl,
      'title': filename,
      'photographer': photographer,
      'creator': photographer,
      'license': license,
      'source': 'upload',
      'is_hero': asHero,
      'width': decoded.width,
      'height': decoded.height,
      'file_size': heroBytes.length,
      'imported_at': DateTime.now().toUtc().toIso8601String(),
      'alt_text': filename,
    }).select('id').single();

    final images = [...destination.images]..removeWhere((u) => u == heroUrl);
    if (asHero) {
      images.insert(0, heroUrl);
    } else {
      images.add(heroUrl);
    }
    await _locations.update(destination.id, {'images': images});

    return ImportResult(
      heroUrl: heroUrl,
      thumbnailUrl: thumbUrl,
      mediumUrl: mediumUrl,
      rehosted: true,
      assetId: (inserted['id'] ?? '').toString(),
      width: decoded.width,
      height: decoded.height,
    );
  }
}

class ImportException implements Exception {
  ImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

final imageImportServiceProvider = Provider<ImageImportService>((ref) {
  return ImageImportService(ref.watch(locationRepositoryProvider));
});
