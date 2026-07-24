import 'package:flutter/material.dart';
import 'package:explorer_os_mobile/shared/components/feature_placeholder.dart';

/// The GPS feature (prepared placeholder, pushed route).
///
/// Location-aware guidance is a future feature. Kept as its own feature folder
/// so the real GPS/location logic can be layered in (services, providers, UI)
/// without disturbing others.
class GpsScreen extends StatelessWidget {
  const GpsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GPS')),
      body: const FeaturePlaceholder(
        icon: Icons.gps_fixed_rounded,
        title: 'GPS Guidance',
        description:
            'Turn-by-turn, location-aware guidance to trails and landmarks is '
            'on the roadmap.',
      ),
    );
  }
}
