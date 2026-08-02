import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:explorer_os_mobile/core/config/env_config.dart';
import 'package:explorer_os_mobile/features/maps/models/driving_distance.dart';

/// Fetches real driving distance + ETA from Google's Distance Matrix API, for
/// the one origin (the traveler) against many destinations (gems/POIs) in a
/// single request per batch.
///
/// WHY THIS EXISTS: [GeoMath.distanceMeters] everywhere else in the app is
/// straight-line ("as the crow flies") — fast, free, always available, and
/// right for radius filtering/ranking. But it can look "wrong" to a traveler
/// comparing it against Google/Apple Maps driving distance, especially near
/// water or where roads have to go around something (rivers, reservoirs,
/// parks). This service adds the *actual road* distance for display, without
/// touching the straight-line math used elsewhere.
///
/// Fails closed: any error (no network, no/invalid key, Distance Matrix API
/// not enabled for the key, over quota, malformed response) returns an empty
/// map rather than throwing — callers should keep showing straight-line
/// distance when this comes back empty.
class DrivingDistanceService {
  DrivingDistanceService({this.getFn = _defaultGet});

  final Future<http.Response> Function(Uri) getFn;

  static Future<http.Response> _defaultGet(Uri uri) =>
      http.get(uri).timeout(const Duration(seconds: 8));

  /// Google's Distance Matrix API caps a single request at 25 destinations
  /// (and 25 origins) per call.
  static const int _maxDestinationsPerRequest = 25;

  /// Looks up driving distance/duration from [originLat],[originLng] to every
  /// point in [destinations] (keyed by whatever id the caller wants back,
  /// e.g. a gem id). Batches requests to respect the API's per-call limit.
  ///
  /// Returns only the destinations Google could route to; missing keys mean
  /// "unknown — fall back to straight-line", not "zero distance".
  Future<Map<String, DrivingDistanceResult>> batchDrivingDistances({
    required double originLat,
    required double originLng,
    required Map<String, ({double lat, double lng})> destinations,
  }) async {
    if (destinations.isEmpty || !EnvConfig.hasGoogleMapsApiKey) return const {};

    final ids = destinations.keys.toList(growable: false);
    final out = <String, DrivingDistanceResult>{};

    for (var start = 0; start < ids.length; start += _maxDestinationsPerRequest) {
      final chunk = ids.sublist(
        start,
        (start + _maxDestinationsPerRequest).clamp(0, ids.length),
      );
      try {
        final result = await _fetchChunk(
          originLat: originLat,
          originLng: originLng,
          ids: chunk,
          destinations: destinations,
        );
        out.addAll(result);
      } catch (_) {
        // One bad chunk shouldn't take down the others already fetched.
      }
    }
    return out;
  }

  Future<Map<String, DrivingDistanceResult>> _fetchChunk({
    required double originLat,
    required double originLng,
    required List<String> ids,
    required Map<String, ({double lat, double lng})> destinations,
  }) async {
    final destParam = ids
        .map((id) => '${destinations[id]!.lat},${destinations[id]!.lng}')
        .join('|');
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/distancematrix/json',
      {
        'origins': '$originLat,$originLng',
        'destinations': destParam,
        'mode': 'driving',
        'units': 'imperial',
        'key': EnvConfig.googleMapsApiKey,
      },
    );

    final res = await getFn(uri);
    if (res.statusCode != 200) return const {};
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return parseDistanceMatrix(body, ids);
  }
}

/// Pure parser for a Google Distance Matrix response — one origin, N
/// destinations, `ids` in the same order the `destinations` param was built.
/// Skips any element whose status isn't OK (e.g. `ZERO_RESULTS`,
/// `NOT_FOUND`) rather than guessing.
Map<String, DrivingDistanceResult> parseDistanceMatrix(
  Map<String, dynamic> json,
  List<String> ids,
) {
  if (json['status'] != 'OK') return const {};
  final rows = json['rows'] as List?;
  if (rows == null || rows.isEmpty) return const {};
  final elements = (rows.first as Map)['elements'] as List?;
  if (elements == null) return const {};

  final out = <String, DrivingDistanceResult>{};
  for (var i = 0; i < elements.length && i < ids.length; i++) {
    final e = elements[i] as Map;
    if (e['status'] != 'OK') continue;
    final distanceMeters = (e['distance'] as Map?)?['value'];
    final durationSeconds = (e['duration'] as Map?)?['value'];
    if (distanceMeters is! num || durationSeconds is! num) continue;
    out[ids[i]] = DrivingDistanceResult(
      distanceMeters: distanceMeters.toDouble(),
      durationSeconds: durationSeconds.toInt(),
    );
  }
  return out;
}

final drivingDistanceServiceProvider =
    Provider<DrivingDistanceService>((ref) => DrivingDistanceService());
