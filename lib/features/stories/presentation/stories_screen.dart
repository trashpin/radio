import 'package:flutter/material.dart';
import 'package:explorer_os_mobile/shared/components/feature_placeholder.dart';

/// The Stories feature (prepared placeholder).
///
/// Home to AI Ranger narratives and destination stories in a future release.
class StoriesScreen extends StatelessWidget {
  const StoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stories')),
      body: const FeaturePlaceholder(
        icon: Icons.auto_stories_rounded,
        title: 'AI Ranger Stories',
        description:
            'Rich, AI-guided stories about the places you visit are coming to '
            'ExplorerOS soon.',
      ),
    );
  }
}
