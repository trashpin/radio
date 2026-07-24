import 'package:flutter/material.dart';
import 'package:explorer_os_mobile/shared/components/feature_placeholder.dart';

/// The Downloads feature (prepared placeholder, pushed route).
///
/// Offline downloads (maps, guides, audio) will let explorers use ExplorerOS
/// without connectivity. Kept as its own feature for the future download
/// manager (services, providers, UI).
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: const FeaturePlaceholder(
        icon: Icons.download_rounded,
        title: 'Offline Downloads',
        description:
            'Save maps, guides, and audio for offline use in the backcountry '
            '— arriving in a future update.',
      ),
    );
  }
}
