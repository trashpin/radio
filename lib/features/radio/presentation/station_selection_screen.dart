import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/features/radio/data/station_preference.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_brand_header.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// Radio station (genre) selection. Choosing a station saves the preference and
/// opens the radio. Every station is GPS-aware travel radio.
class StationSelectionScreen extends ConsumerWidget {
  const StationSelectionScreen({super.key});

  static const String _blurb =
      "Hear today's top music and local stories based on your GPS.";

  static const _stations = <(IconData, String)>[
    (Icons.music_note_rounded, 'Country'),
    (Icons.graphic_eq_rounded, 'Rock'),
    (Icons.trending_up_rounded, 'Top Hits'),
    (Icons.child_care_rounded, 'Kids'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(stationPreferenceProvider);
    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(RD.lg, RD.md, RD.lg, 0),
                  child: RadioBrandHeader(showNotificationDot: false),
                ),
                const SizedBox(height: RD.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: RD.xl),
                  child: Text('Choose your station', style: RD.title),
                ),
                const SizedBox(height: RD.md),
                Expanded(
                  child: GridView.count(
                    padding: const EdgeInsets.all(RD.lg),
                    crossAxisCount: 2,
                    mainAxisSpacing: RD.md,
                    crossAxisSpacing: RD.md,
                    childAspectRatio: 0.95,
                    children: [
                      for (final (icon, name) in _stations)
                        StationCard(
                          icon: icon,
                          name: name,
                          description: _blurb,
                          selected: selected == name,
                          onTap: () => _choose(context, ref, name),
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

  Future<void> _choose(BuildContext context, WidgetRef ref, String name) async {
    await ref.read(stationPreferenceProvider.notifier).select(name);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$name station selected')));
    context.go(AppRoute.radio.path);
  }
}
