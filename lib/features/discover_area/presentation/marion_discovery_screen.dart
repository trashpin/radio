import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/admin/species_images/wildlife_placeholder.dart';
import 'package:explorer_os_mobile/features/discover_area/controllers/area_content_playback_controller.dart';
import 'package:explorer_os_mobile/features/discover_area/models/area_content_block.dart';
import 'package:explorer_os_mobile/features/discover_area/presentation/marion_nature_screen.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// The Marion County "Marion County" location row — the single source for the
/// History narration + the page's imagery. Marion-only by design (no GPS area
/// detection): we resolve THE county row rather than "the area you're in".
final marionCountyProvider = Provider<MasterLocation?>((ref) {
  final all = ref.watch(masterLocationsProvider).value ?? const [];
  for (final l in all) {
    if (l.type == LocationType.county &&
        (l.county ?? '').toLowerCase().trim() == 'marion' &&
        l.active) {
      return l;
    }
  }
  return null;
});

/// Plays a single narration through the shared area playback controller
/// (recorded audio when present, on-device TTS otherwise). One tap = one
/// museum-guide narration; a new tap replaces the current one.
void playDiscoveryNarration(
  WidgetRef ref, {
  required String title,
  String? script,
  String? audioUrl,
  List<String> images = const [],
}) {
  ref.read(areaContentPlaybackControllerProvider.notifier).play([
    AreaContentBlock(
      id: 'marion:${title.toLowerCase()}',
      locationId: 'marion',
      categoryToken: 'discover',
      title: title,
      narrationScript: script,
      audioUrl: audioUrl,
      images: images,
    ),
  ]);
}

/// "Discover This Area" → the polished, Marion-County-only discovery page.
/// Two large sections: History (a narrated museum-guide history of the county)
/// and Nature (wildlife, plants, springs and parks to explore).
class MarionDiscoveryScreen extends ConsumerWidget {
  const MarionDiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final marion = ref.watch(marionCountyProvider);
    final playing = ref.watch(areaContentPlaybackControllerProvider).current;
    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Column(
          children: [
            const RadioSubPageBar(title: 'Discover Marion County'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(RD.lg, RD.sm, RD.lg, RD.xl),
                children: [
                  Text('Marion County, Florida',
                      style: RD.title.copyWith(fontSize: 24)),
                  const SizedBox(height: RD.xs),
                  Text(
                    'Your personal local historian and park ranger — tap to '
                    'listen and explore.',
                    style: RD.body,
                  ),
                  const SizedBox(height: RD.lg),
                  _HistoryCard(marion: marion),
                  const SizedBox(height: RD.lg),
                  _NatureCard(marion: marion),
                ],
              ),
            ),
            if (playing != null) _NowNarrating(title: playing.title),
          ],
        ),
      ),
    );
  }
}

class _HistoryCard extends ConsumerWidget {
  const _HistoryCard({required this.marion});
  final MasterLocation? marion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final script = (marion?.narrationScript ?? '').trim();
    final short = marion?.shortDescription ??
        'How Marion County was founded, where its name came from, and the '
            'landmarks that make it special.';
    final img = (marion?.images.isNotEmpty ?? false) ? marion!.images.first : null;
    final canPlay = script.isNotEmpty ||
        (marion?.audioFiles.isNotEmpty ?? false) ||
        (marion?.bestDescription != null);
    return _BigCard(
      imageUrl: img,
      placeholderLabel: 'Marion County',
      icon: Icons.history_edu_rounded,
      title: 'History',
      subtitle: short,
      actionLabel: 'Play',
      actionIcon: Icons.play_arrow_rounded,
      onAction: !canPlay || marion == null
          ? null
          : () => playDiscoveryNarration(
                ref,
                title: 'Marion County History',
                script: script.isNotEmpty ? script : marion!.bestDescription,
                audioUrl: marion!.audioFiles.isNotEmpty
                    ? marion!.audioFiles.first
                    : null,
                images: marion!.images,
              ),
    );
  }
}

class _NatureCard extends StatelessWidget {
  const _NatureCard({required this.marion});
  final MasterLocation? marion;

  @override
  Widget build(BuildContext context) {
    final img = (marion?.images.length ?? 0) > 1
        ? marion!.images[1]
        : ((marion?.images.isNotEmpty ?? false) ? marion!.images.first : null);
    return _BigCard(
      imageUrl: img,
      placeholderLabel: 'Marion Nature',
      placeholderCategory: 'nature',
      icon: Icons.forest_rounded,
      title: 'Nature',
      subtitle: 'Wildlife, birds, reptiles, plants, springs and parks — '
          'explore the natural side of Marion County.',
      actionLabel: 'Explore',
      actionIcon: Icons.arrow_forward_rounded,
      onAction: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const MarionNatureScreen()),
      ),
    );
  }
}

/// Reusable large image card used for both History and Nature.
class _BigCard extends StatelessWidget {
  const _BigCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
    this.imageUrl,
    this.placeholderLabel,
    this.placeholderCategory,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;
  final String? imageUrl;
  final String? placeholderLabel;
  final String? placeholderCategory;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final placeholder = WildlifePlaceholder(
        label: placeholderLabel, category: placeholderCategory);
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: url == null || url.isEmpty
                  ? placeholder
                  : Image.network(url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => placeholder),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(RD.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(icon, color: RD.textPrimary, size: 22),
                  const SizedBox(width: RD.sm),
                  Text(title, style: RD.title.copyWith(fontSize: 22)),
                ]),
                const SizedBox(height: RD.sm),
                Text(subtitle, style: RD.body),
                const SizedBox(height: RD.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onAction,
                    icon: Icon(actionIcon),
                    label: Text(actionLabel),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A slim bar showing what's currently narrating, with a Stop control.
class _NowNarrating extends ConsumerWidget {
  const _NowNarrating({required this.title});
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: RD.panel,
      padding: const EdgeInsets.fromLTRB(RD.lg, RD.sm, RD.sm, RD.sm),
      child: Row(children: [
        const Icon(Icons.graphic_eq_rounded, color: RD.green, size: 18),
        const SizedBox(width: RD.sm),
        Expanded(
          child: Text('Narrating: $title',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: RD.body.copyWith(color: RD.textPrimary)),
        ),
        TextButton(
          onPressed: () =>
              ref.read(areaContentPlaybackControllerProvider.notifier).stop(),
          child: const Text('Stop'),
        ),
      ]),
    );
  }
}
