import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/admin/species_images/wildlife_placeholder.dart';
import 'package:explorer_os_mobile/features/discover_area/models/area_discovery_category.dart';
import 'package:explorer_os_mobile/features/discover_area/models/discovery_area.dart';
import 'package:explorer_os_mobile/features/discover_area/providers/area_species_provider.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/discovery/observation_controller.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// Wildlife, Birds, and Plants & Trees all share this screen — a grid over
/// the EXISTING Species catalog (see [areaSpeciesProvider]), not a new
/// content system. Tapping a species narrates it through
/// [ObservationController] — the exact same mechanism "I See Something"
/// already uses — then returns to the radio.
class AreaSpeciesScreen extends ConsumerWidget {
  const AreaSpeciesScreen({super.key, required this.area, required this.category});
  final DiscoveryArea area;
  final AreaDiscoveryCategory category;

  void _pick(BuildContext context, WidgetRef ref, Species s) {
    ref.read(observationControllerProvider.notifier).observe(s);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(areaSpeciesProvider(category.token));
    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Column(
          children: [
            RadioSubPageBar(title: category.label, subtitle: area.name),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _empty(),
                data: (species) {
                  if (species.isEmpty) return _empty();
                  return GridView.builder(
                    padding: const EdgeInsets.all(RD.lg),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: RD.sm,
                      mainAxisSpacing: RD.sm,
                      childAspectRatio: 0.82,
                    ),
                    itemCount: species.length,
                    itemBuilder: (context, i) {
                      final s = species[i];
                      return _SpeciesCard(
                        species: s,
                        onTap: () => _pick(context, ref, s),
                      );
                    },
                  );
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
            Icon(category.icon, size: 56, color: RD.textSecondary),
            const SizedBox(height: RD.lg),
            Text('No ${category.label.toLowerCase()} catalogued for this area yet.',
                textAlign: TextAlign.center, style: RD.title.copyWith(fontSize: 18)),
          ],
        ),
      ),
    );
  }
}

class _SpeciesCard extends StatelessWidget {
  const _SpeciesCard({required this.species, required this.onTap});
  final Species species;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(RD.rMd)),
              child: species.heroImageUrl == null
                  ? WildlifePlaceholder(
                      category: species.category, label: species.commonName)
                  : Image.network(
                      species.heroImageUrl!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => WildlifePlaceholder(
                          category: species.category, label: species.commonName),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(RD.sm),
            child: Text(
              species.commonName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: RD.cardTitle.copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
