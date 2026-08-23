import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/ocala_forest/models/forest_location.dart';
import 'package:explorer_os_mobile/features/ocala_forest/presentation/widgets/forest_audio_bar.dart';
import 'package:explorer_os_mobile/features/ocala_forest/presentation/widgets/forest_location_detail_sheet.dart';
import 'package:explorer_os_mobile/features/ocala_forest/providers/ocala_forest_providers.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// DISCOVERIES — every forest location that isn't a trail stop or a story
/// (`experienceType == 'discovery'`: springs, lakes, historic sites, and
/// everything else spec section 3 lists), grouped by [ForestLocation.category].
/// Tapping any entry opens the shared detail sheet (Listen/Tell Me
/// More/Navigate) — the same sheet the Explorer Map already uses.
class ForestDiscoveriesScreen extends ConsumerWidget {
  const ForestDiscoveriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationsAsync = ref.watch(forestLocationsProvider);
    final locations = (locationsAsync.value ?? const <ForestLocation>[])
        .where((l) => l.isDiscovery && l.active)
        .toList();

    final grouped = <String, List<ForestLocation>>{};
    for (final l in locations) {
      grouped.putIfAbsent(l.category, () => []).add(l);
    }
    final categories = grouped.keys.toList()..sort();

    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Column(
          children: [
            const RadioSubPageBar(
                title: 'Discoveries', subtitle: 'Ocala National Forest'),
            const Padding(
              padding: EdgeInsets.fromLTRB(RD.lg, RD.sm, RD.lg, 0),
              child: ForestAudioBar(),
            ),
            Expanded(
              child: locationsAsync.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : categories.isEmpty
                      ? Center(
                          child: Text('Nothing to discover here yet.',
                              style: RD.body.copyWith(color: RD.textSecondary)),
                        )
                      : ListView(
                          padding: const EdgeInsets.all(RD.lg),
                          children: [
                            for (final category in categories) ...[
                              Text(category.toUpperCase(),
                                  style: RD.badge.copyWith(
                                      color: RD.textSecondary, letterSpacing: 1.1)),
                              const SizedBox(height: RD.sm),
                              for (final loc in grouped[category]!) ...[
                                _DiscoveryTile(location: loc),
                                const SizedBox(height: RD.sm),
                              ],
                              const SizedBox(height: RD.md),
                            ],
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoveryTile extends ConsumerWidget {
  const _DiscoveryTile({required this.location});
  final ForestLocation location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassPanel(
      onTap: () => showForestLocationDetail(context, ref, location),
      child: Row(
        children: [
          const Icon(Icons.park_rounded, color: RD.greenBright),
          const SizedBox(width: RD.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(location.name, style: RD.cardTitle.copyWith(color: Colors.white)),
                if ((location.description ?? '').trim().isNotEmpty)
                  Text(location.description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RD.caption.copyWith(color: RD.textSecondary)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: RD.textFaint),
        ],
      ),
    );
  }
}
