import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_boundary.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_location.dart';
import 'package:explorer_os_mobile/features/ocala_forest/providers/ocala_forest_providers.dart';

/// OCALA NATIONAL FOREST EXPLORER — a completely isolated experimental page
/// (own route `/ocala-forest`, own providers, own Supabase tables). Reuses,
/// without modifying: `google_maps_flutter` (the same map package
/// `MapsScreen` already uses, just the app's first `Polygon` usage), the
/// existing `gpsControllerProvider` GPS stream, and the existing generic
/// admin DB Tools table browser (see `db_tools.dart`) for data management.
///
/// Keeps the interface deliberately simple per spec section 6 — the
/// important thing for v1 is that the geographic filtering (a REAL,
/// authoritative USFS boundary, not a circle or Marion County substitute)
/// actually works.
class OcalaForestScreen extends ConsumerWidget {
  const OcalaForestScreen({super.key});

  static const _initialCenter = LatLng(29.15, -81.75); // Ocala NF, roughly
  static const _initialZoom = 10.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boundaryAsync = ref.watch(ocalaForestBoundaryProvider);
    final locationsAsync = ref.watch(forestLocationsProvider);
    final hasGpsFix = ref.watch(gpsControllerProvider).location != null;
    final insideForest = ref.watch(isInsideOcalaForestProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('OCALA NATIONAL FOREST EXPLORER'),
        backgroundColor: const Color(0xFF1B3B24),
        foregroundColor: Colors.white,
      ),
      body: boundaryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load the forest boundary: $e')),
        data: (boundary) {
          if (boundary == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No forest boundary is loaded yet. Run migration '
                  '0048_ocala_forest.sql to seed the Ocala National Forest '
                  'boundary.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final locations = locationsAsync.value ?? const <ForestLocation>[];
          return Column(
            children: [
              _StatusBanner(hasGpsFix: hasGpsFix, insideForest: insideForest),
              Expanded(
                child: _ForestMap(boundary: boundary, locations: locations),
              ),
            ],
          );
        },
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

class _ForestMap extends StatelessWidget {
  const _ForestMap({required this.boundary, required this.locations});
  final ForestBoundary boundary;
  final List<ForestLocation> locations;

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

  Set<Marker> _markers(BuildContext context) {
    return {
      for (final loc in locations)
        Marker(
          markerId: MarkerId(loc.id),
          position: LatLng(loc.latitude, loc.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(_hueForCategory(loc.category)),
          infoWindow: InfoWindow(title: loc.name, snippet: loc.category),
          onTap: () => _showDetail(context, loc),
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

  void _showDetail(BuildContext context, ForestLocation loc) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(loc.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(loc.category,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      letterSpacing: 1.1,
                      color: Colors.grey.shade600,
                    )),
            if ((loc.description ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(loc.description!.trim()),
            ],
            if ((loc.source ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Source: ${loc.source}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      )),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: const CameraPosition(
        target: OcalaForestScreen._initialCenter,
        zoom: OcalaForestScreen._initialZoom,
      ),
      polygons: _polygons(),
      markers: _markers(context),
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      mapType: MapType.terrain,
    );
  }
}
