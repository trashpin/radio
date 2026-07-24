import 'package:flutter/material.dart';

import '../../shared/widgets/coming_soon_view.dart';

/// The Radio tab (placeholder).
///
/// Explorer Radio is explicitly OUT OF SCOPE for Phase 1, so this screen only
/// shows the shared "Coming Soon" placeholder. The tab exists now so the
/// bottom navigation is complete; the real audio experience will replace this
/// widget in a later phase.
class RadioScreen extends StatelessWidget {
  const RadioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: ComingSoonView(featureName: 'Radio', icon: Icons.radio_outlined),
    );
  }
}
