import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/gps/providers/gps_status_provider.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/discovery/nearby_narration_controller.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// "I See Something" — NOT a camera. Presents nature/heritage categories; tapping
/// one starts a live GPS-based narration of nearby possibilities, then returns
/// to the radio (where the report plays and "Back to radio" resumes the music).
class ISeeSomethingScreen extends ConsumerWidget {
  const ISeeSomethingScreen({super.key});

  static const _categories = <(IconData, String)>[
    (Icons.pets_rounded, 'Wildlife'),
    (Icons.flutter_dash_rounded, 'Birds'),
    (Icons.park_rounded, 'Trees'),
    (Icons.local_florist_rounded, 'Plants'),
    (Icons.filter_vintage_rounded, 'Flowers'),
    (Icons.set_meal_rounded, 'Fish'),
    (Icons.history_edu_rounded, 'History'),
    (Icons.apartment_rounded, 'Buildings'),
    (Icons.account_balance_rounded, 'Landmarks'),
    (Icons.more_horiz_rounded, 'Other'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const RadioSubPageBar(
                  title: 'I See Something',
                  subtitle: 'What are you looking at? Pick a category and I\'ll '
                      'tell you what\'s around you.',
                ),
                Expanded(
                  child: GridView.count(
                    padding: const EdgeInsets.all(RD.lg),
                    crossAxisCount: 3,
                    mainAxisSpacing: RD.md,
                    crossAxisSpacing: RD.md,
                    childAspectRatio: 0.95,
                    children: [
                      for (final (icon, label) in _categories)
                        CategoryTile(
                          icon: icon,
                          label: label,
                          onTap: () => _start(context, ref, label),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _start(BuildContext context, WidgetRef ref, String category) {
    // Kick GPS and begin a nearby narration; the radio interrupts to report.
    ref.read(gpsStatusProvider.notifier).requestAndStart();
    ref.read(nearbyNarrationControllerProvider.notifier).narrateNearest();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Listening for $category around you…')),
    );
    Navigator.of(context).maybePop();
  }
}
