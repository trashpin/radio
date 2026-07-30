import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:explorer_os_mobile/features/admin/media_search/models/image_search_result.dart';

/// Wikimedia Commons image search via the MediaWiki API. `origin=*` enables
/// CORS, and `upload.wikimedia.org` serves images with permissive CORS headers,
/// so both search AND byte download work from Flutter web.
class WikimediaClient {
  WikimediaClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _base = 'https://commons.wikimedia.org/w/api.php';

  Future<List<ImageSearchResult>> search(
    String query, {
    int limit = 40,
    int thumbWidth = 400,
  }) async {
    final uri = Uri.parse(_base).replace(queryParameters: {
      'action': 'query',
      'format': 'json',
      'origin': '*',
      'generator': 'search',
      'gsrsearch': 'filetype:bitmap $query',
      'gsrnamespace': '6', // File:
      'gsrlimit': '$limit',
      'prop': 'imageinfo',
      'iiprop': 'url|size|mime|extmetadata',
      'iiurlwidth': '$thumbWidth',
    });
    final res = await _client.get(uri, headers: const {
      'Accept': 'application/json',
    });
    if (res.statusCode != 200) {
      throw http.ClientException(
          'Wikimedia ${res.statusCode}: ${res.body}', uri);
    }
    return parse(jsonDecode(res.body));
  }

  /// Pure parse of a MediaWiki `query` response with `generator=search` +
  /// `prop=imageinfo`.
  static List<ImageSearchResult> parse(dynamic body) {
    final pages = (body is Map ? body['query'] : null);
    final map = (pages is Map ? pages['pages'] : null);
    if (map is! Map) return const [];
    final out = <ImageSearchResult>[];
    for (final entry in map.values) {
      if (entry is! Map) continue;
      final info = entry['imageinfo'];
      if (info is! List || info.isEmpty) continue;
      final ii = info.first;
      if (ii is! Map) continue;
      final url = (ii['url'] ?? '').toString();
      if (url.isEmpty) continue;
      final meta = (ii['extmetadata'] is Map)
          ? ii['extmetadata'] as Map
          : const {};
      final title = (entry['title'] ?? 'File')
          .toString()
          .replaceFirst(RegExp(r'^File:'), '')
          .replaceAll('_', ' ');
      out.add(ImageSearchResult(
        source: ImageSource.wikimedia,
        id: 'wikimedia:${entry['pageid'] ?? title}',
        title: title,
        imageUrl: url,
        thumbnailUrl: (ii['thumburl'] ?? url).toString(),
        width: (ii['width'] as num?)?.toInt(),
        height: (ii['height'] as num?)?.toInt(),
        photographer: _meta(meta, 'Artist'),
        license: _meta(meta, 'LicenseShortName'),
        licenseUrl: _meta(meta, 'LicenseUrl'),
        foreignLandingUrl: (ii['descriptionurl'] ?? '').toString().isEmpty
            ? null
            : ii['descriptionurl'].toString(),
        mimeType: ii['mime']?.toString(),
        fileSize: (ii['size'] as num?)?.toInt(),
        description: _meta(meta, 'ImageDescription'),
      ));
    }
    return out;
  }

  /// Reads a Commons extmetadata value and strips its HTML wrapper.
  static String? _meta(Map meta, String key) {
    final v = meta[key];
    if (v is! Map) return null;
    final raw = v['value']?.toString();
    if (raw == null || raw.isEmpty) return null;
    final text = raw
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return text.isEmpty ? null : text;
  }
}
