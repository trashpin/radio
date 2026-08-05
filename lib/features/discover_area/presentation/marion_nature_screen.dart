import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/admin/species_images/wildlife_placeholder.dart';
import 'package:explorer_os_mobile/features/discover_area/presentation/marion_discovery_screen.dart';
import 'package:explorer_os_mobile/features/discovery/data/species_repository.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/discover_area/controllers/area_content_playback_controller.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// A Nature section backed by the Species catalog (Wildlife, Birds, …).
class _SpeciesSectionDef {
  const _SpeciesSectionDef(this.title, this.token);
  final String title;
  final String token; // species.category
}

/// A Nature section backed by master locations (Springs, State Parks, …).
class _LocationSectionDef {
  const _LocationSectionDef(this.title, this.types);
  final String title;
  final Set<LocationType> types;
}

// The requested Nature sections, in order. Species sections with no data yet
// (e.g. Mammals/Trees/Wildflowers until species are categorized) simply don't
// render, so the page always looks complete.
const _speciesSections = <_SpeciesSectionDef>[
  _SpeciesSectionDef('Wildlife', 'animals'),
  _SpeciesSectionDef('Birds', 'birds'),
  _SpeciesSectionDef('Mammals', 'mammals'),
  _SpeciesSectionDef('Reptiles', 'reptiles'),
  _SpeciesSectionDef('Fish', 'fish'),
  _SpeciesSectionDef('Trees', 'trees'),
  _SpeciesSectionDef('Wildflowers', 'wildflowers'),
  _SpeciesSectionDef('Native Plants', 'plants'),
];

const _locationSections = <_LocationSectionDef>[
  _LocationSectionDef('Springs', {LocationType.spring}),
  _LocationSectionDef('State Parks', {LocationType.statePark}),
  _LocationSectionDef(
      'County Parks', {LocationType.countyPark, LocationType.cityPark}),
];

/// Marion County → Nature. Education & discovery: tap Play on any wildlife,
/// plant, spring or park to hear a short narrated introduction.
class MarionNatureScreen extends ConsumerWidget {
  const MarionNatureScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(areaContentPlaybackControllerProvider).current;
    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Column(
          children: [
            const RadioSubPageBar(
              title: 'Nature',
              subtitle: 'Marion County, Florida',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(RD.lg, RD.sm, RD.lg, RD.xl),
                children: [
                  for (final s in _speciesSections)
                    _SpeciesSection(def: s),
                  for (final s in _locationSections)
                    _LocationSection(def: s),
                ],
              ),
            ),
            if (playing != null) _NowNarratingBar(title: playing.title),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, this.count);
  final String title;
  final int count;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: RD.lg, bottom: RD.sm),
        child: Row(children: [
          Text(title, style: RD.title.copyWith(fontSize: 20)),
          const SizedBox(width: RD.sm),
          Text('$count', style: RD.body.copyWith(color: RD.textFaint)),
        ]),
      );
}

class _SpeciesSection extends ConsumerWidget {
  const _SpeciesSection({required this.def});
  final _SpeciesSectionDef def;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(speciesByCategoryProvider(def.token));
    final list = async.value ?? const <Species>[];
    if (list.isEmpty) return const SizedBox.shrink(); // hide empty sections
    final shown = list.take(20).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(def.title, list.length),
        for (final sp in shown)
          _ItemCard(
            imageUrl: sp.heroImageUrl,
            placeholderCategory: sp.category,
            title: sp.commonName,
            subtitle: _speciesSubtitle(sp),
            onPlay: () => playDiscoveryNarration(
              ref,
              title: sp.commonName,
              script: _speciesScript(sp),
              images: sp.heroImageUrl == null ? const [] : [sp.heroImageUrl!],
            ),
          ),
      ],
    );
  }
}

class _LocationSection extends ConsumerWidget {
  const _LocationSection({required this.def});
  final _LocationSectionDef def;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(masterLocationsProvider).value ?? const [];
    final list = [
      for (final l in all)
        if (l.active &&
            !l.hidden &&
            !l.isPublishBlocked &&
            def.types.contains(l.type))
          l,
    ]..sort((a, b) => a.name.compareTo(b.name));
    if (list.isEmpty) return const SizedBox.shrink();
    final shown = list.take(30).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(def.title, list.length),
        for (final l in shown)
          _ItemCard(
            imageUrl: l.images.isNotEmpty ? l.images.first : null,
            placeholderCategory: 'nature',
            title: l.name,
            subtitle: l.shortDescription ?? l.bestDescription ?? l.type.label,
            onPlay: () => playDiscoveryNarration(
              ref,
              title: l.name,
              script: (l.narrationScript ?? '').trim().isNotEmpty
                  ? l.narrationScript
                  : l.bestDescription,
              audioUrl: l.audioFiles.isNotEmpty ? l.audioFiles.first : null,
              images: l.images,
            ),
          ),
      ],
    );
  }
}

String _speciesSubtitle(Species s) {
  final d = (s.description ?? '').trim();
  if (d.isNotEmpty) return d;
  return s.scientificName ?? 'A species of Marion County, Florida.';
}

String _speciesScript(Species s) {
  final parts = <String>[];
  final d = (s.description ?? '').trim();
  parts.add(d.isNotEmpty
      ? d
      : '${s.commonName}${s.scientificName != null ? ', ${s.scientificName},' : ''} '
          'is found here in Marion County, Florida.');
  final f = (s.funFacts ?? '').trim();
  if (f.isNotEmpty) parts.add('Here\'s a fun fact: $f');
  return parts.join(' ');
}

/// A compact list card: thumbnail + name + short description + Play.
class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.title,
    required this.subtitle,
    required this.onPlay,
    this.imageUrl,
    this.placeholderCategory,
  });
  final String title;
  final String subtitle;
  final VoidCallback onPlay;
  final String? imageUrl;
  final String? placeholderCategory;

  @override
  Widget build(BuildContext context) {
    final ph = WildlifePlaceholder(
        category: placeholderCategory, label: title, compact: true);
    return Padding(
      padding: const EdgeInsets.only(bottom: RD.sm),
      child: GlassPanel(
        padding: const EdgeInsets.all(RD.sm),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 64,
              height: 64,
              child: imageUrl == null || imageUrl!.isEmpty
                  ? ph
                  : Image.network(imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => ph),
            ),
          ),
          const SizedBox(width: RD.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RD.body.copyWith(
                        color: RD.textPrimary, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: RD.body.copyWith(fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            onPressed: onPlay,
            icon: const Icon(Icons.play_circle_fill_rounded,
                color: RD.green, size: 34),
            tooltip: 'Play',
          ),
        ]),
      ),
    );
  }
}

class _NowNarratingBar extends ConsumerWidget {
  const _NowNarratingBar({required this.title});
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
