import 'package:flutter/material.dart';
import 'package:explorer_os_mobile/shared/components/feature_placeholder.dart';

/// The Radio tab (prepared placeholder).
///
/// Explorer Radio (ranger stories, live audio guides) is a future feature.
/// Renders the shared [FeaturePlaceholder] until the audio experience is built.
class RadioScreen extends StatelessWidget {
  const RadioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Radio')),
      body: const FeaturePlaceholder(
        icon: Icons.radio_rounded,
        title: 'Explorer Radio',
        description:
            'Ranger-narrated stories and live audio guides that play as you '
            'travel — coming soon.',
      ),
    );
  }
}
