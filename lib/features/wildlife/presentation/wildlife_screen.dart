import 'package:flutter/material.dart';
import 'package:explorer_os_mobile/shared/components/feature_placeholder.dart';

/// The Wildlife feature (prepared placeholder).
///
/// Will surface species guides and wildlife sightings for each destination.
class WildlifeScreen extends StatelessWidget {
  const WildlifeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wildlife')),
      body: const FeaturePlaceholder(
        icon: Icons.pets_rounded,
        title: 'Wildlife Guide',
        description:
            'Species guides and recent sightings for each destination are on '
            'the way.',
      ),
    );
  }
}
