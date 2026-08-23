import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:explorer_os_mobile/features/ocala_forest/models/forest_trail.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// The actual imported U.S. Forest Service trail geometry for ONE trail,
/// rendered on the EXISTING map system (google_maps_flutter — the same
/// package/widget `OcalaExplorerMapScreen` already uses) — used whenever a
/// trail has no official printable map attached (spec §2's fallback path:
/// "Use the existing Forest Service trail geometry already imported... Do
/// NOT manually draw an approximate trail"). This never draws anything the
/// source didn't provide: every point plotted is a real vertex from
/// `forest_trails.geom`.
class ForestTrailMapScreen extends StatefulWidget {
  const ForestTrailMapScreen({super.key, required this.trail});
  final ForestTrail trail;

  @override
  State<ForestTrailMapScreen> createState() => _ForestTrailMapScreenState();
}

class _ForestTrailMapScreenState extends State<ForestTrailMapScreen> {
  GoogleMapController? _controller;

  LatLngBounds? _bounds() {
    double? minLat, maxLat, minLng, maxLng;
    for (final part in widget.trail.parts) {
      for (final p in part) {
        minLat = minLat == null ? p.lat : (p.lat < minLat ? p.lat : minLat);
        maxLat = maxLat == null ? p.lat : (p.lat > maxLat ? p.lat : maxLat);
        minLng = minLng == null ? p.lng : (p.lng < minLng ? p.lng : minLng);
        maxLng = maxLng == null ? p.lng : (p.lng > maxLng ? p.lng : maxLng);
      }
    }
    if (minLat == null) return null;
    return LatLngBounds(
      southwest: LatLng(minLat, minLng!),
      northeast: LatLng(maxLat!, maxLng!),
    );
  }

  Set<Polyline> _polylines() {
    final out = <Polyline>{};
    for (var i = 0; i < widget.trail.parts.length; i++) {
      final part = widget.trail.parts[i];
      if (part.length < 2) continue;
      out.add(Polyline(
        polylineId: PolylineId('trail-part-$i'),
        points: [for (final p in part) LatLng(p.lat, p.lng)],
        color: const Color(0xFFF2B33D),
        width: 5,
      ));
    }
    return out;
  }

  Set<Marker> _markers() {
    final t = widget.trail;
    if (!t.hasGeometricStart) return {};
    return {
      Marker(
        markerId: const MarkerId('geometric-start'),
        position: LatLng(t.geometricStartLat!, t.geometricStartLng!),
        infoWindow: const InfoWindow(
          title: 'Trail line start point',
          snippet: 'A geometric fact, not an official trailhead facility',
        ),
      ),
    };
  }

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;
    final bounds = _bounds();
    if (bounds != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 48));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.trail;
    final bounds = _bounds();
    final initialCenter = bounds != null
        ? LatLng(
            (bounds.southwest.latitude + bounds.northeast.latitude) / 2,
            (bounds.southwest.longitude + bounds.northeast.longitude) / 2,
          )
        : const LatLng(29.15, -81.75);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            RadioSubPageBar(
              title: (t.trailName?.trim().isNotEmpty ?? false) ? t.trailName! : 'Trail ${t.trailNo}',
              subtitle: 'U.S. Forest Service trail geometry',
            ),
            Expanded(
              child: t.parts.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No trail geometry is available for this trail.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : GoogleMap(
                      initialCameraPosition: CameraPosition(target: initialCenter, zoom: 12),
                      onMapCreated: _onMapCreated,
                      polylines: _polylines(),
                      markers: _markers(),
                      mapType: MapType.terrain,
                      myLocationEnabled: true,
                      myLocationButtonEnabled: true,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
