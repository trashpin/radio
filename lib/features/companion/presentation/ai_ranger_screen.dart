import 'package:flutter/material.dart';

import 'package:explorer_os_mobile/shared/components/feature_placeholder.dart';

/// The AI Ranger tab.
///
/// The AI Ranger is ExplorerOS's intelligent companion (backed by the GPS
/// Intelligence Engine + AI Producer). The conversational UI is not built yet,
/// so this renders the shared [FeaturePlaceholder]; swapping in the real
/// experience later is a one-line change in the router.
class AiRangerScreen extends StatelessWidget {
  const AiRangerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Ranger')),
      body: const FeaturePlaceholder(
        icon: Icons.smart_toy_rounded,
        title: 'AI Ranger',
        description:
            'Your intelligent trail companion — ask questions, get stories, '
            'and hear what matters as you travel.',
      ),
    );
  }
}
