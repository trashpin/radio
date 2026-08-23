import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_boundary.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_location.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_trail.dart';
import 'package:explorer_os_mobile/features/ocala_forest/presentation/widgets/forest_location_detail_sheet.dart';
import 'package:explorer_os_mobile/features/ocala_forest/providers/ocala_forest_providers.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// EXPLORER MAP — v1's original map-first view (real USFS boundary polygon
/// + location markers + live GPS position), now one tile in the Ocala
/// Forest Explorer hub rather than the entire experience. Unchanged from
/// v1 otherwise.
class OcalaExplorerMapScreen extends ConsumerWidget {
  const OcalaExplorerMapScreen({super.key});

  static const _initialCenter = LatLng(29.15, -81.75); // Ocala NF, roughly
  static const _initialZoom = 10.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boundaryAsync = ref.watch(ocalaForestBoundaryProvider);
    final locationsAsync = ref.watch(forestLocationsProvider);
    final hasGpsFix = ref.watch(gpsControllerProvider).location != null;
    final insideForest = ref.watch(isInsideOcalaForestProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const RadioSubPageBar(title: 'Explorer Map', subtitle: 'Ocala National Forest'),
            _StatusBanner(hasGpsFix: hasGpsFix, insideForest: insideForest),
            Expanded(
              child: boundaryAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text('Could not load the forest boundary: $e')),
                data: (boundary) {
                  if (boundary == null) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No forest boundary is loaded yet. Run migration '
                          '0048_ocala_forest.sql to seed the Ocala National '
                          'Forest boundary.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  final locations = locationsAsync.value ?? const <ForestLocation>[];
                  final trails = ref.watch(forestTrailsProvider).value ?? const <ForestTrail>[];
                  return _ForestMap(boundary: boundary, locations: locations, trails: trails);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.hasGpsFix, required this.insideForest});
  final bool hasGpsFix;
  final bool? insideForest;

  @override
  Widget build(BuildContext context) {
    final String text;
    final Color color;
    if (!hasGpsFix) {
      text = 'Waiting for a GPS fix…';
      color = Colors.grey.shade700;
    } else if (insideForest == true) {
      text = '🌲 You are INSIDE Ocala National Forest';
      color = const Color(0xFF2E7D32);
    } else {
      text = '📍 You are OUTSIDE Ocala National Forest';
      color = Colors.grey.shade700;
    }
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Text(text,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
    );
  }
}

class _ForestMap extends ConsumerWidget {
  const _ForestMap({required this.boundary, required this.locations, this.trails = const []});
  final ForestBoundary boundary;
  final List<ForestLocation> locations;
  final List<ForestTrail> trails;

  Set<Polyline> _polylines() {
    final out = <Polyline>{};
    for (final trail in trails) {
      for (var i = 0; i < trail.parts.length; i++) {
        final part = trail.parts[i];
        if (part.length < 2) continue;
        out.add(Polyline(
          polylineId: PolylineId('trail-${trail.id}-$i'),
          points: [for (final p in part) LatLng(p.lat, p.lng)],
          color: const Color(0xFFF2B33D),
          width: 3,
          consumeTapEvents: true,
        ));
      }
    }
    return out;
  }

  Set<Polygon> _polygons() {
    final out = <Polygon>{};
    for (var i = 0; i < boundary.parts.length; i++) {
      final part = boundary.parts[i];
      out.add(Polygon(
        polygonId: PolygonId('ocala-forest-$i'),
        points: [for (final p in part.outer.points) LatLng(p.lat, p.lng)],
        holes: [
          for (final hole in part.holes)
            [for (final p in hole.points) LatLng(p.lat, p.lng)],
        ],
        strokeColor: const Color(0xFF2E7D32),
        strokeWidth: 2,
        fillColor: const Color(0x332E7D32),
      ));
    }
    return out;
  }

  Set<Marker> _markers(BuildContext context, WidgetRef ref) {
    return {
      for (final loc in locations)
        Marker(
          markerId: MarkerId(loc.id),
          position: LatLng(loc.latitude, loc.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(_hueForCategory(loc.category)),
          infoWindow: InfoWindow(title: loc.name, snippet: loc.category),
          onTap: () => showForestLocationDetail(context, ref, loc),
        ),
    };
  }

  double _hueForCategory(String category) {
    final c = category.toLowerCase();
    if (c.contains('spring')) return BitmapDescriptor.hueAzure;
    if (c.contains('lake') || c.contains('river') || c.contains('water')) {
      return BitmapDescriptor.hueBlue;
    }
    if (c.contains('trail')) return BitmapDescriptor.hueOrange;
    if (c.contains('camp')) return BitmapDescriptor.hueYellow;
    return BitmapDescriptor.hueGreen;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GoogleMap(
      initialCameraPosition: const CameraPosition(
        target: OcalaExplorerMapScreen._initialCenter,
        zoom: OcalaExplorerMapScreen._initialZoom,
      ),
      polygons: _polygons(),
      polylines: _polylines(),
      markers: _markers(context, ref),
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      mapType: MapType.terrain,
    );
  }
}
