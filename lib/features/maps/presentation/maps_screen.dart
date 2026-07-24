import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:explorer_os_mobile/features/destinations/providers/destinations_provider.dart';
import 'package:explorer_os_mobile/shared/models/destination.dart';

/// The Map tab.
///
/// Renders a Google Map and plots every destination that has coordinates
/// (Base44 `latitude`/`longitude`). The map itself always renders — markers are
/// added when destinations load, so the map is useful even before/without
/// backend content. Tapping a marker shows the destination name/location.
class MapsScreen extends ConsumerWidget {
  const MapsScreen({super.key});

  /// Fallback camera target (central Florida) used until a destination with
  /// coordinates is available to center on.
  static const _fallbackCenter = LatLng(29.1872, -81.7137);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destinationsAsync = ref.watch(destinationsProvider);
    final destinations = destinationsAsync.value ?? const <Destination>[];

    final markers = <Marker>{
      for (final d in destinations.where((d) => d.hasCoordinates))
        Marker(
          markerId: MarkerId(d.id),
          position: LatLng(d.latitude!, d.longitude!),
          infoWindow: InfoWindow(title: d.name, snippet: d.location),
        ),
    };

    final initialTarget =
        markers.isNotEmpty ? markers.first.position : _fallbackCenter;

    return Scaffold(
      appBar: AppBar(title: const Text('Map')),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: initialTarget,
              zoom: markers.isNotEmpty ? 9 : 7,
            ),
            markers: markers,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
          ),
          if (destinationsAsync.isLoading)
            const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
