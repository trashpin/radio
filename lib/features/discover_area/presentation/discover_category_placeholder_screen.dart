import 'package:flutter/material.dart';

import 'package:explorer_os_mobile/features/discover_area/models/area_discovery_category.dart';
import 'package:explorer_os_mobile/features/discover_area/models/discovery_area.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// Shown when a Discover This Area category is tapped but its narrated
/// experience isn't built yet. Deliberately honest (no fake content) —
/// each later phase replaces this with the real experience for its
/// category by swapping the destination in [DiscoverAreaScreen], not by
/// changing the grid itself.
class DiscoverCategoryPlaceholderScreen extends StatelessWidget {
  const DiscoverCategoryPlaceholderScreen({
    super.key,
    required this.area,
    required this.category,
  });

  final DiscoveryArea area;
  final AreaDiscoveryCategory category;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Column(
          children: [
            RadioSubPageBar(title: category.label, subtitle: area.name),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(RD.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: category.tint.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: category.tint.withValues(alpha: 0.5)),
                        ),
                        child: Icon(category.icon, color: category.tint, size: 36),
                      ),
                      const SizedBox(height: RD.lg),
                      Text(
                        '${category.label} for ${area.name}',
                        textAlign: TextAlign.center,
                        style: RD.title.copyWith(fontSize: 20),
                      ),
                      const SizedBox(height: RD.sm),
                      Text(
                        "This narrated experience isn't built yet — coming in "
                        'a future update.',
                        textAlign: TextAlign.center,
                        style: RD.body,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
