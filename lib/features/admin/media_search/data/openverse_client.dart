import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:explorer_os_mobile/features/admin/media_search/logic/image_filters.dart';
import 'package:explorer_os_mobile/features/admin/media_search/models/image_search_result.dart';

/// Openverse image search (https://api.openverse.org). No API key required for
/// anonymous, rate-limited access; CORS is enabled so it works from Flutter web.
class OpenverseClient {
  OpenverseClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _base = 'https://api.openverse.org/v1/images/';

  Future<List<ImageSearchResult>> search(
    String query, {
    int pageSize = 40,
    ImageSort sort = ImageSort.relevance,
    bool commercialOnly = false,
  }) async {
    final params = <String, String>{
      'q': query,
      'page_size': '$pageSize',
      'mature': 'false',
      // Prefer the good stuff first; Openverse doesn't expose "popular" so we
      // approximate newest/popular via source ordering downstream.
      if (commercialOnly) 'license_type': 'commercial',
    };
    final uri = Uri.parse(_base).replace(queryParameters: params);
    final res = await _client.get(uri, headers: const {
      'Accept': 'application/json',
    });
    if (res.statusCode != 200) {
      throw http.ClientException(
          'Openverse ${res.statusCode}: ${res.body}', uri);
    }
    return parse(jsonDecode(res.body));
  }

  /// Pure parse of an Openverse `/v1/images` response body.
  static List<ImageSearchResult> parse(dynamic body) {
    final results = (body is Map ? body['results'] : null);
    if (results is! List) return const [];
    final out = <ImageSearchResult>[];
    for (final r in results) {
      if (r is! Map) continue;
      final url = (r['url'] ?? '').toString();
      if (url.isEmpty) continue;
      out.add(ImageSearchResult(
        source: ImageSource.openverse,
        id: 'openverse:${r['id']}',
        title: (r['title'] ?? 'Untitled').toString(),
        imageUrl: url,
        thumbnailUrl: (r['thumbnail'] ?? url).toString(),
        width: (r['width'] as num?)?.toInt(),
        height: (r['height'] as num?)?.toInt(),
        photographer: (r['creator'] ?? '').toString().trim().isEmpty
            ? null
            : r['creator'].toString(),
        license: _license(r),
        licenseUrl: r['license_url']?.toString(),
        foreignLandingUrl: r['foreign_landing_url']?.toString(),
        mimeType: r['filetype']?.toString(),
        fileSize: (r['filesize'] as num?)?.toInt(),
        description: (r['attribution'] ?? '').toString(),
      ));
    }
    return out;
  }

  static String _license(Map r) {
    final lic = (r['license'] ?? '').toString().toLowerCase();
    final ver = (r['license_version'] ?? '').toString();
    if (lic.isEmpty) return 'Unknown';
    if (lic == 'pdm' || lic == 'cc0') {
      return lic == 'cc0' ? 'CC0 (Public Domain)' : 'Public Domain Mark';
    }
    final label = 'CC ${lic.toUpperCase()}';
    return ver.isEmpty ? label : '$label $ver';
  }
}
