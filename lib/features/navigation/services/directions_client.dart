import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:explorer_os_mobile/core/config/env_config.dart';
import 'package:explorer_os_mobile/features/navigation/models/route_plan.dart';

/// Fetches a driving route from Google's Directions API — the same
/// [EnvConfig.googleMapsApiKey] already used client-side for the Maps SDK and
/// [DrivingDistanceService]'s Distance Matrix calls. Requires "Directions
/// API" to be enabled for that key (the same key already had "Places API"
/// enabled for What Is That?'s Google Places integration).
///
/// This client is used ONLY to build the piecewise-linear route + turn
/// instructions `TripTracker` needs to detect maneuvers/off-route/arrival —
/// this feature ships no map UI, so the full encoded overview polyline is
/// never decoded; each step's own start/end point is a perfectly adequate,
/// much simpler polyline for off-route distance checks.
///
/// Fails closed: any error (no network, no/invalid key, API not enabled,
/// over quota, malformed response, `ZERO_RESULTS`) returns null.
class DirectionsClient {
  DirectionsClient({this.getFn = _defaultGet});

  final Future<http.Response> Function(Uri) getFn;

  static Future<http.Response> _defaultGet(Uri uri) =>
      http.get(uri).timeout(const Duration(seconds: 10));

  Future<RoutePlan?> route({
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
    String? destinationName,
  }) async {
    if (!EnvConfig.hasGoogleMapsApiKey) return null;
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
        'origin': '$originLat,$originLng',
        'destination': '$destinationLat,$destinationLng',
        'mode': 'driving',
        'key': EnvConfig.googleMapsApiKey,
      });
      final res = await getFn(uri);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return parseDirectionsResponse(body, destinationName: destinationName);
    } catch (_) {
      return null;
    }
  }
}

/// Pure parser for a Google Directions API response's first route/leg.
RoutePlan? parseDirectionsResponse(
  Map<String, dynamic> json, {
  String? destinationName,
}) {
  if (json['status'] != 'OK') return null;
  final routes = json['routes'] as List?;
  if (routes == null || routes.isEmpty) return null;
  final legs = (routes.first as Map)['legs'] as List?;
  if (legs == null || legs.isEmpty) return null;
  final leg = legs.first as Map;
  final rawSteps = leg['steps'] as List?;
  if (rawSteps == null || rawSteps.isEmpty) return null;

  final steps = <RouteStep>[];
  final polyline = <({double lat, double lng})>[];
  for (final raw in rawSteps) {
    final s = raw as Map;
    final start = s['start_location'] as Map?;
    final end = s['end_location'] as Map?;
    if (start == null || end == null) continue;
    final startLat = (start['lat'] as num?)?.toDouble();
    final startLng = (start['lng'] as num?)?.toDouble();
    final endLat = (end['lat'] as num?)?.toDouble();
    final endLng = (end['lng'] as num?)?.toDouble();
    if (startLat == null || startLng == null || endLat == null || endLng == null) {
      continue;
    }
    final distance = (s['distance'] as Map?)?['value'];
    steps.add(RouteStep(
      instruction: _stripHtml(s['html_instructions']?.toString() ?? ''),
      maneuver: ManeuverKind.fromGoogle(s['maneuver']?.toString()),
      distanceMeters: (distance is num) ? distance.toDouble() : 0,
      startLat: startLat,
      startLng: startLng,
      endLat: endLat,
      endLng: endLng,
    ));
    if (polyline.isEmpty) polyline.add((lat: startLat, lng: startLng));
    polyline.add((lat: endLat, lng: endLng));
  }
  if (steps.isEmpty) return null;

  final totalDistance = (leg['distance'] as Map?)?['value'];
  final totalDuration = (leg['duration'] as Map?)?['value'];
  final encodedOverview =
      ((routes.first as Map)['overview_polyline'] as Map?)?['points']?.toString();

  return RoutePlan(
    steps: steps,
    polyline: polyline,
    totalDistanceMeters: (totalDistance is num) ? totalDistance.toDouble() : 0,
    totalDurationSeconds: (totalDuration is num) ? totalDuration.toInt() : null,
    destinationName: destinationName,
    overviewPolyline: (encodedOverview == null || encodedOverview.isEmpty)
        ? const []
        : decodePolyline(encodedOverview),
  );
}

final _tagPattern = RegExp(r'<[^>]*>');

String _stripHtml(String html) =>
    html.replaceAll(_tagPattern, '').replaceAll('&nbsp;', ' ').trim();

/// Decodes Google's polyline encoding (the standard algorithm — see
/// https://developers.google.com/maps/documentation/utilities/polylinealgorithm)
/// into real lat/lng points along the actual road shape. A pure function,
/// independently testable, deliberately hand-written rather than pulling in
/// a dependency for ~20 lines of well-known, stable math.
List<({double lat, double lng})> decodePolyline(String encoded) {
  final points = <({double lat, double lng})>[];
  var index = 0;
  var lat = 0;
  var lng = 0;

  while (index < encoded.length) {
    var shift = 0;
    var result = 0;
    int b;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    final dLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lat += dLat;

    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    final dLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lng += dLng;

    points.add((lat: lat / 1e5, lng: lng / 1e5));
  }
  return points;
}

final directionsClientProvider =
    Provider<DirectionsClient>((ref) => DirectionsClient());
