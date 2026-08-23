import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/admin/media_search/logic/image_ranking.dart';
import 'package:explorer_os_mobile/features/admin/media_search/models/image_search_result.dart';
import 'package:explorer_os_mobile/features/events/data/event_repository.dart';
import 'package:explorer_os_mobile/features/events/models/local_event.dart';

/// Downloads, resizes, re-hosts, records (with full attribution), and
/// assigns an open-license image to an event's `image_url` — the same
/// pipeline [ImageImportService] already runs for locations
/// (media_search/data/image_import_service.dart), applied to `events`
/// instead. Kept as its own small class rather than generalizing that one,
/// since events have a single `image_url` (not a `images` gallery) and a
/// different backing repository/table — duplicating this much smaller
/// upload routine is lower-risk than reshaping an already-working class.
class EventImageImportService {
  EventImageImportService(this._events, {http.Client? client})
      : _client = client ?? http.Client();

  final EventRepository _events;
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
    LocalEvent event, {
    int minWidth = kMinImageWidth,
  }) async {
    final folder = 'events/${_slug(event.name)}';
    final base = '${_slug(result.title)}_${DateTime.now().millisecondsSinceEpoch}';

    String heroUrl;
    String thumbUrl;
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
          throw EventImageImportException(
              'Image is only ${width}px wide (minimum ${minWidth}px).');
        }
        final heroBytes = decoded.width > 2000
            ? Uint8List.fromList(
                img.encodeJpg(img.copyResize(decoded, width: 2000), quality: 88))
            : bytes;
        final thumbBytes = Uint8List.fromList(img.encodeJpg(
            img.copyResize(decoded, width: decoded.width < 400 ? decoded.width : 400),
            quality: 80));

        heroUrl = await _upload('$folder/${base}_hero.jpg', heroBytes, 'image/jpeg');
        thumbUrl = await _upload('$folder/${base}_thumb.jpg', thumbBytes, 'image/jpeg');
        storagePath = '$folder/${base}_hero.jpg';
        fileSize = heroBytes.length;
      } else {
        heroUrl = result.imageUrl;
        thumbUrl = result.thumbnailUrl;
      }
    } else {
      heroUrl = result.imageUrl;
      thumbUrl = result.thumbnailUrl;
    }

    // Record the asset with full attribution — same table/shape the
    // location import path already writes, just record_type 'event'.
    await SupabaseService.client.from('media_assets').insert({
      'destination_id': event.id,
      'record_type': 'event',
      'media_type': 'image',
      'storage_path': ?storagePath,
      'public_url': heroUrl,
      'thumbnail': thumbUrl,
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

    await _events.update(event.id, {'image_url': heroUrl});
    return heroUrl;
  }
}

class EventImageImportException implements Exception {
  EventImageImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

final eventImageImportServiceProvider = Provider<EventImageImportService>(
  (ref) => EventImageImportService(ref.watch(eventRepositoryProvider)),
);
