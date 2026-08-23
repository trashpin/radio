import 'package:flutter/material.dart';

import 'package:explorer_os_mobile/features/ocala_forest/discover/models/discovery_category.dart';
import 'package:explorer_os_mobile/features/ocala_forest/discover/presentation/forest_discover_capture_screen.dart';
import 'package:explorer_os_mobile/features/ocala_forest/discover/presentation/forest_discovery_map_screen.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// DISCOVER home (spec §2) — pick a category, then take/pick a photo. Kept
/// deliberately simple and mobile-friendly: one grid, one tap to advance.
class ForestDiscoverHomeScreen extends StatelessWidget {
  const ForestDiscoverHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Column(
          children: [
            const RadioSubPageBar(title: '🔎 Discover', subtitle: 'Ocala National Forest'),
            Padding(
              padding: const EdgeInsets.fromLTRB(RD.lg, RD.sm, RD.lg, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'See something interesting? Snap a photo and find out what it is.',
                      style: RD.body.copyWith(color: RD.textSecondary),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ForestDiscoveryMapScreen())),
                    icon: const Icon(Icons.map_outlined, size: 18, color: RD.green),
                    label: const Text('Map', style: TextStyle(color: RD.green)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.count(
                padding: const EdgeInsets.all(RD.lg),
                crossAxisCount: 2,
                mainAxisSpacing: RD.md,
                crossAxisSpacing: RD.md,
                childAspectRatio: 1.15,
                children: [
                  for (final group in DiscoveryGroup.values)
                    _CategoryTile(
                      group: group,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ForestDiscoverCaptureScreen(group: group))),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.group, required this.onTap});
  final DiscoveryGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(group.emoji, style: const TextStyle(fontSize: 36)),
          const SizedBox(height: RD.sm),
          Text(
            group.label,
            textAlign: TextAlign.center,
            style: RD.cardTitle.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}
