import 'package:flutter/material.dart';

import '../../shared/widgets/coming_soon_view.dart';

/// The Map tab (placeholder).
///
/// Offline Maps is explicitly OUT OF SCOPE for Phase 1, so this screen only
/// shows the shared "Coming Soon" placeholder. Keeping the tab in the app now
/// means the navigation layout is final and future work can drop the real map
/// UI in without changing routing.
class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: ComingSoonView(featureName: 'Map', icon: Icons.map_outlined),
    );
  }
}
