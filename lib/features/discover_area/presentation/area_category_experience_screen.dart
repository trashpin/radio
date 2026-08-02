import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/admin/species_images/wildlife_placeholder.dart';
import 'package:explorer_os_mobile/features/discover_area/controllers/area_content_playback_controller.dart';
import 'package:explorer_os_mobile/features/discover_area/data/area_content_repository.dart';
import 'package:explorer_os_mobile/features/discover_area/models/area_content_block.dart';
import 'package:explorer_os_mobile/features/discover_area/models/area_discovery_category.dart';
import 'package:explorer_os_mobile/features/discover_area/models/discovery_area.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// A narrated, image-backed experience for one Discover This Area category
/// (History, Nature, Geology — any category backed by
/// `area_discovery_content`). Plays its blocks in sequence through
/// [AreaContentPlaybackController], syncing the shown image/text to whatever
/// is currently narrating.
class AreaCategoryExperienceScreen extends ConsumerStatefulWidget {
  const AreaCategoryExperienceScreen({
    super.key,
    required this.area,
    required this.category,
  });

  final DiscoveryArea area;
  final AreaDiscoveryCategory category;

  @override
  ConsumerState<AreaCategoryExperienceScreen> createState() =>
      _AreaCategoryExperienceScreenState();
}

class _AreaCategoryExperienceScreenState
    extends ConsumerState<AreaCategoryExperienceScreen> {
  bool _started = false;

  // Captured in initState so dispose() never touches `ref` (unsafe after
  // unmount) — a lazy `late` field would initialize during dispose if build
  // never read it.
  late final AreaContentPlaybackController _playback;

  @override
  void initState() {
    super.initState();
    _playback = ref.read(areaContentPlaybackControllerProvider.notifier);
  }

  @override
  void dispose() {
    // Leaving the screen always stops playback and hands control back to the
    // normal radio — never leaves a stray narration running in background.
    _playback.stop();
    super.dispose();
  }

  void _maybeStart(List<AreaContentBlock> blocks) {
    if (_started || blocks.isEmpty) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playback.play(blocks);
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(areaContentForCategoryProvider(
      (locationId: widget.area.location.id, categoryToken: widget.category.token),
    ));
    final playback = ref.watch(areaContentPlaybackControllerProvider);

    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Column(
          children: [
            RadioSubPageBar(title: widget.category.label, subtitle: widget.area.name),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _empty(),
                data: (blocks) {
                  if (blocks.isEmpty) return _empty();
                  _maybeStart(blocks);
                  final current = playback.current ?? blocks.first;
                  return _player(current, playback, blocks.length);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RD.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.category.icon, size: 56, color: RD.textSecondary),
            const SizedBox(height: RD.lg),
            Text('${widget.category.label} for ${widget.area.name}',
                textAlign: TextAlign.center, style: RD.title.copyWith(fontSize: 20)),
            const SizedBox(height: RD.sm),
            Text(
              'No narrated content has been added for this category yet.',
              textAlign: TextAlign.center,
              style: RD.body,
            ),
          ],
        ),
      ),
    );
  }

  Widget _player(
    AreaContentBlock current,
    AreaContentPlaybackState playback,
    int total,
  ) {
    final index = playback.blocks.isEmpty
        ? 0
        : playback.blocks.indexWhere((b) => b.id == current.id).clamp(0, total - 1);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(RD.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(RD.rMd),
                    child: current.heroImage == null
                        ? WildlifePlaceholder(label: current.title)
                        : Image.network(
                            current.heroImage!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                WildlifePlaceholder(label: current.title),
                          ),
                  ),
                ),
                const SizedBox(height: RD.lg),
                if (total > 1)
                  Text('${index + 1} of $total', style: RD.badge.copyWith(color: RD.textSecondary)),
                const SizedBox(height: RD.xs),
                Text(current.title, style: RD.title.copyWith(fontSize: 22)),
                if ((current.narrationScript ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: RD.md),
                  Text(current.narrationScript!, style: RD.body),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(RD.lg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (playback.hasNext)
                FilledButton.icon(
                  onPressed: () => ref
                      .read(areaContentPlaybackControllerProvider.notifier)
                      .skipToNext(),
                  icon: const Icon(Icons.skip_next_rounded),
                  label: const Text('Next'),
                )
              else
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Done'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
