import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/admin/species_images/wildlife_placeholder.dart';
import 'package:explorer_os_mobile/features/discover_area/models/area_discovery_category.dart';
import 'package:explorer_os_mobile/features/discover_area/models/discovery_area.dart';
import 'package:explorer_os_mobile/features/discover_area/models/tour_mode.dart';
import 'package:explorer_os_mobile/features/discover_area/presentation/area_attractions_screen.dart';
import 'package:explorer_os_mobile/features/discover_area/presentation/area_category_experience_screen.dart';
import 'package:explorer_os_mobile/features/discover_area/presentation/area_species_screen.dart';
import 'package:explorer_os_mobile/features/discover_area/presentation/area_tour_screen.dart';
import 'package:explorer_os_mobile/features/discover_area/presentation/audio_experience_screen.dart';
import 'package:explorer_os_mobile/features/discover_area/presentation/discover_category_placeholder_screen.dart';
import 'package:explorer_os_mobile/features/discover_area/providers/discovery_area_provider.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart' show formatDistance;
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// "Discover This Area" — a location-aware discovery hub for wherever the
/// traveler currently is (area detection: [currentDiscoveryAreaProvider]).
/// Shows the area's hero info, then a grid of narrated-experience categories.
/// Tapping a category navigates to its dedicated experience — see
/// [_destinationFor], the single place later phases plug in the real
/// content, one category at a time, without touching this screen otherwise.
class DiscoverAreaScreen extends ConsumerWidget {
  const DiscoverAreaScreen({super.key});

  Widget _destinationFor(AreaDiscoveryCategory category, DiscoveryArea area) {
    // History/Nature/Geology, Wildlife/Birds/Plants & Trees, Attractions,
    // Audio Experience, and the Driving/Walking Tours are all wired to real
    // data now — every category has a real destination.
    switch (category.token) {
      case 'history':
      case 'nature':
      case 'geology':
        return AreaCategoryExperienceScreen(area: area, category: category);
      case 'wildlife':
      case 'birds':
      case 'plants_trees':
        return AreaSpeciesScreen(area: area, category: category);
      case 'attractions':
        return AreaAttractionsScreen(area: area);
      case 'audio_experience':
        return AudioExperienceScreen(area: area);
      case 'driving_tour':
        return AreaTourScreen(area: area, mode: TourMode.driving);
      case 'walking_tour':
        return AreaTourScreen(area: area, mode: TourMode.walking);
      default:
        return DiscoverCategoryPlaceholderScreen(area: area, category: category);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final area = ref.watch(currentDiscoveryAreaProvider);
    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: area == null
            ? const _NoAreaState()
            : _AreaContent(area: area, onCategoryTap: (cat) {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => _destinationFor(cat, area),
                ));
              }),
      ),
    );
  }
}

class _NoAreaState extends StatelessWidget {
  const _NoAreaState();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const RadioSubPageBar(title: 'Discover This Area'),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(RD.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.explore_off_rounded,
                      size: 56, color: RD.textSecondary),
                  const SizedBox(height: RD.lg),
                  Text('No area detected here yet',
                      textAlign: TextAlign.center,
                      style: RD.title.copyWith(fontSize: 20)),
                  const SizedBox(height: RD.sm),
                  Text(
                    "We haven't mapped a discovery area for your current "
                    'location. Keep exploring — more areas are added '
                    'regularly.',
                    textAlign: TextAlign.center,
                    style: RD.body,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AreaContent extends StatelessWidget {
  const _AreaContent({required this.area, required this.onCategoryTap});
  final DiscoveryArea area;
  final void Function(AreaDiscoveryCategory) onCategoryTap;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(RD.sm, RD.sm, RD.sm, 0),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: RD.textPrimary),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ]),
          ),
        ),
        SliverToBoxAdapter(child: _Hero(area: area)),
        SliverPadding(
          padding: const EdgeInsets.all(RD.lg),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(area.name, style: RD.title.copyWith(fontSize: 26)),
                if (area.shortIntroduction != null) ...[
                  const SizedBox(height: RD.sm),
                  Text(area.shortIntroduction!, style: RD.body),
                ],
                const SizedBox(height: RD.md),
                Row(children: [
                  GlassChip(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.near_me_rounded, size: 14, color: RD.textPrimary),
                      const SizedBox(width: 4),
                      Text(
                        area.isCurrentlyInside
                            ? "You're here"
                            : formatDistance(area.distanceMeters),
                        style: RD.badge.copyWith(color: RD.textPrimary),
                      ),
                    ]),
                  ),
                  const SizedBox(width: RD.sm),
                  if (area.estimatedListeningMinutes > 0)
                    GlassChip(
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.headphones_rounded,
                            size: 14, color: RD.textPrimary),
                        const SizedBox(width: 4),
                        Text('~${area.estimatedListeningMinutes} min',
                            style: RD.badge.copyWith(color: RD.textPrimary)),
                      ]),
                    ),
                ]),
                const SizedBox(height: RD.lg),
                Text('Explore', style: RD.title.copyWith(fontSize: 18)),
                const SizedBox(height: RD.sm),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(RD.lg, 0, RD.lg, RD.xl),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: RD.sm,
              mainAxisSpacing: RD.sm,
              childAspectRatio: 0.85,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final cat = areaDiscoveryCategories[i];
                return CategoryTile(
                  icon: cat.icon,
                  label: cat.label,
                  tint: cat.tint,
                  onTap: () => onCategoryTap(cat),
                );
              },
              childCount: areaDiscoveryCategories.length,
            ),
          ),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.area});
  final DiscoveryArea area;

  @override
  Widget build(BuildContext context) {
    final url = area.heroImageUrl;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: url == null
          ? WildlifePlaceholder(label: area.name)
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => WildlifePlaceholder(label: area.name),
            ),
    );
  }
}
