import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:explorer_os_mobile/features/ocala_forest/discover/models/discovery_category.dart';
import 'package:explorer_os_mobile/features/ocala_forest/discover/models/forest_discovery_report.dart';
import 'package:explorer_os_mobile/features/ocala_forest/discover/providers/forest_discovery_providers.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// 🗺️ DISCOVERY MAP (spec §9) — community discoveries, filterable by
/// category. Reads only `forest_discovery_reports_public`, so every pin
/// already has its coordinates correctly generalized for anything not
/// fully public (spec §10) — this screen never sees or needs the exact
/// location of a sensitive discovery.
class ForestDiscoveryMapScreen extends ConsumerStatefulWidget {
  const ForestDiscoveryMapScreen({super.key});

  @override
  ConsumerState<ForestDiscoveryMapScreen> createState() => _ForestDiscoveryMapScreenState();
}

class _ForestDiscoveryMapScreenState extends ConsumerState<ForestDiscoveryMapScreen> {
  static const _initialCenter = LatLng(29.15, -81.75);
  final Set<DiscoveryGroup> _active = DiscoveryGroup.values.toSet();

  @override
  Widget build(BuildContext context) {
    final discoveriesAsync = ref.watch(forestDiscoveriesProvider);
    final all = discoveriesAsync.value ?? const <ForestDiscoveryReport>[];
    final visible = [
      for (final d in all)
        if (_active.contains(DiscoveryGroup.fromId(d.category) ?? DiscoveryGroup.other)) d,
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const RadioSubPageBar(title: 'Discovery Map', subtitle: 'Ocala National Forest'),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: RD.lg, vertical: RD.xs),
                children: [
                  for (final g in DiscoveryGroup.values) ...[
                    RadioFilterChip(
                      label: '${g.emoji} ${g.label}',
                      selected: _active.contains(g),
                      onTap: () => setState(() {
                        if (_active.contains(g)) {
                          _active.remove(g);
                        } else {
                          _active.add(g);
                        }
                      }),
                    ),
                    const SizedBox(width: RD.xs),
                  ],
                ],
              ),
            ),
            Expanded(
              child: GoogleMap(
                initialCameraPosition: const CameraPosition(target: _initialCenter, zoom: 10),
                mapType: MapType.terrain,
                myLocationEnabled: true,
                markers: {
                  for (final d in visible)
                    Marker(
                      markerId: MarkerId(d.id),
                      position: LatLng(d.latitude, d.longitude),
                      icon: BitmapDescriptor.defaultMarkerWithHue(_hueFor(d.category)),
                      infoWindow: InfoWindow(
                        title: d.displayName,
                        snippet: d.locationGeneralized
                            ? 'Recently discovered in this general area'
                            : 'Reported nearby',
                      ),
                    ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _hueFor(String categoryId) {
    switch (DiscoveryGroup.fromId(categoryId)) {
      case DiscoveryGroup.wildlife:
        return BitmapDescriptor.hueOrange;
      case DiscoveryGroup.birds:
        return BitmapDescriptor.hueAzure;
      case DiscoveryGroup.plantsNature:
        return BitmapDescriptor.hueGreen;
      case DiscoveryGroup.water:
        return BitmapDescriptor.hueBlue;
      case DiscoveryGroup.geology:
        return BitmapDescriptor.hueYellow;
      case DiscoveryGroup.history:
        return BitmapDescriptor.hueViolet;
      case DiscoveryGroup.other:
      case null:
        return BitmapDescriptor.hueRose;
    }
  }
}
