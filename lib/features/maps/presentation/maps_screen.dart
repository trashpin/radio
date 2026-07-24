import 'package:flutter/material.dart';
import 'package:explorer_os_mobile/shared/components/feature_placeholder.dart';

/// The Map tab (prepared placeholder).
///
/// Offline Maps is a future feature. This screen renders the shared
/// [FeaturePlaceholder]; when the real map is built, only this widget changes —
/// navigation stays untouched.
class MapsScreen extends StatelessWidget {
  const MapsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Map')),
      body: const FeaturePlaceholder(
        icon: Icons.map_rounded,
        title: 'Maps',
        description:
            'Interactive and offline trail maps are on the way — explore '
            'destinations, trails, and points of interest.',
      ),
    );
  }
}
