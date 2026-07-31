import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:explorer_os_mobile/features/admin/species_images/wildlife_placeholder.dart';
import 'package:explorer_os_mobile/features/gps/providers/gps_status_provider.dart';
import 'package:explorer_os_mobile/features/nearby_gems/data/nearby_gems_repository.dart';
import 'package:explorer_os_mobile/features/nearby_gems/models/nearby_gem.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/discovery/gem_narration_controller.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// Nearby Gems — shows ONLY admin-approved gems from the ExplorerOS database
/// (`nearby_gems`), that are ACTIVE and within the configured distance, sorted
/// nearest-first. Nothing is imported from Google Places or any third party.
class LocalGemsScreen extends ConsumerStatefulWidget {
  const LocalGemsScreen({super.key});
  @override
  ConsumerState<LocalGemsScreen> createState() => _LocalGemsScreenState();
}

class _LocalGemsScreenState extends ConsumerState<LocalGemsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gpsStatusProvider.notifier).requestAndStart();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hits = ref.watch(nearbyGemsForUserProvider);
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
                  title: 'Nearby Gems',
                  subtitle: 'ExplorerOS-approved places worth discovering.',
                ),
                Expanded(
                  child: hits.isEmpty
                      ? _empty()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                            RD.lg,
                            0,
                            RD.lg,
                            RD.xl,
                          ),
                          itemCount: hits.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: RD.lg),
                          itemBuilder: (_, i) => _GemCard(
                            gem: hits[i].gem,
                            distanceMeters: hits[i].distanceMeters,
                            onHearStory: () => _hearStory(hits[i].gem),
                            onNavigate: () => _navigate(hits[i].gem),
                            onOpen: () => _hearStory(hits[i].gem),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty() => Center(
    child: Padding(
      padding: const EdgeInsets.all(RD.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.diamond_outlined, size: 48, color: RD.greenDim),
          const SizedBox(height: RD.md),
          Text(
            'No ExplorerOS Gems nearby yet. More discoveries await as you '
            'travel.',
            textAlign: TextAlign.center,
            style: RD.body.copyWith(fontSize: 15),
          ),
        ],
      ),
    ),
  );

  /// Tapping a gem expands its featured image into the ExplorerOS Radio
  /// "Now Playing" view and begins narration (recorded audio → generated
  /// speech → Long Description), then returns to the radio so the traveler
  /// watches the story play. Reuses the existing radio audio engine.
  void _hearStory(NearbyGem gem) {
    if (!gem.canNarrate) return;
    ref.read(gemNarrationControllerProvider.notifier).narrateGem(gem);
    // Return to the radio interface so the Now Playing hero is visible.
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _navigate(NearbyGem gem) async {
    if (!gem.hasCoordinates) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query='
      '${gem.latitude},${gem.longitude}',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open navigation')),
      );
    }
  }
}

class _GemCard extends StatelessWidget {
  const _GemCard({
    required this.gem,
    required this.distanceMeters,
    required this.onHearStory,
    required this.onNavigate,
    required this.onOpen,
  });
  final NearbyGem gem;
  final double distanceMeters;
  final VoidCallback onHearStory;
  final VoidCallback onNavigate;
  final VoidCallback onOpen;

  String get _miles {
    final mi = distanceMeters / 1609.344;
    return mi < 10 ? '${mi.toStringAsFixed(1)} mi' : '${mi.round()} mi';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RD.panel,
      borderRadius: RD.brLg,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: gem.canNarrate ? onOpen : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Large featured image with the ExplorerOS badge + distance overlays.
            SizedBox(
              height: 180,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SpeciesImageOrPlaceholder(
                    url: gem.featuredImage,
                    category: gem.category,
                    label: gem.name,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xCC000000)],
                        stops: [0.5, 1],
                      ),
                    ),
                  ),
                  if ((gem.badge ?? '').isNotEmpty)
                    Positioned(
                      top: RD.sm,
                      left: RD.sm,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: RD.sm,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: RD.green,
                          borderRadius: BorderRadius.circular(RD.rPill),
                        ),
                        child: Text(
                          gem.badge!.toUpperCase(),
                          style: RD.badge.copyWith(color: RD.onGreen),
                        ),
                      ),
                    ),
                  Positioned(
                    top: RD.sm,
                    right: RD.sm,
                    child: GlassChip(
                      padding: const EdgeInsets.symmetric(
                        horizontal: RD.sm,
                        vertical: 4,
                      ),
                      child: Text(
                        _miles,
                        style: RD.badge.copyWith(color: RD.textPrimary),
                      ),
                    ),
                  ),
                  Positioned(
                    left: RD.md,
                    right: RD.md,
                    bottom: RD.sm,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          gem.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: RD.cardTitle.copyWith(fontSize: 18),
                        ),
                        if ((gem.category ?? '').isNotEmpty)
                          Text(
                            gem.category!,
                            style: RD.caption.copyWith(color: Colors.white),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(RD.md),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: gem.hasStory ? RD.green : RD.panelAlt,
                        foregroundColor: gem.hasStory
                            ? RD.onGreen
                            : RD.textSecondary,
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: gem.hasStory ? onHearStory : null,
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: Text(
                        gem.hasStory ? 'Hear Story' : 'Story coming soon',
                      ),
                    ),
                  ),
                  const SizedBox(width: RD.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        foregroundColor: RD.textPrimary,
                        side: const BorderSide(color: RD.stroke),
                      ),
                      onPressed: gem.hasCoordinates ? onNavigate : null,
                      icon: const Icon(Icons.navigation_rounded, size: 18),
                      label: const Text('Navigate'),
                    ),
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
