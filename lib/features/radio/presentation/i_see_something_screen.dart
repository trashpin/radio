import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/discovery/data/species_repository.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';
import 'package:explorer_os_mobile/features/gps/providers/gps_status_provider.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/discovery/nearby_narration_controller.dart';
import 'package:explorer_os_mobile/features/radio/discovery/observation_controller.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// A discovery category → the `species.category` token it loads.
class _Cat {
  const _Cat(this.icon, this.label, this.token);
  final IconData icon;
  final String label;
  final String token;
}

const _categories = <_Cat>[
  _Cat(Icons.pets_rounded, 'Wildlife', 'animals'),
  _Cat(Icons.flutter_dash_rounded, 'Birds', 'birds'),
  _Cat(Icons.park_rounded, 'Trees', 'trees'),
  _Cat(Icons.local_florist_rounded, 'Plants', 'plants'),
  _Cat(Icons.filter_vintage_rounded, 'Flowers', 'wildflowers'),
  _Cat(Icons.set_meal_rounded, 'Fish', 'fish'),
  _Cat(Icons.emoji_nature_rounded, 'Reptiles', 'reptiles'),
  _Cat(Icons.history_edu_rounded, 'History', 'historic_sites'),
  _Cat(Icons.account_balance_rounded, 'Landmarks', 'landmarks'),
  _Cat(Icons.more_horiz_rounded, 'Other', 'other'),
];

/// "I See Something" — NOT a camera. Pick a category to see the wildlife / plants
/// / etc. documented around you (photo + name); tap one to hear its narration on
/// the radio (recorded voiceover if available, else spoken), then it resumes.
class ISeeSomethingScreen extends ConsumerStatefulWidget {
  const ISeeSomethingScreen({super.key});
  @override
  ConsumerState<ISeeSomethingScreen> createState() =>
      _ISeeSomethingScreenState();
}

class _ISeeSomethingScreenState extends ConsumerState<ISeeSomethingScreen> {
  _Cat? _selected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gpsStatusProvider.notifier).requestAndStart();
    });
  }

  void _pickSpecies(Species s) {
    // Narrate the subject on the radio (recorded audio or TTS), then return.
    ref.read(observationControllerProvider.notifier).observe(s);
    Navigator.of(context).maybePop();
  }

  void _narrateNearby() {
    ref.read(nearbyNarrationControllerProvider.notifier).narrateNearest();
    final msg = ref.read(nearbyNarrationControllerProvider).message;
    if (msg != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selected;
    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _bar(sel),
                Expanded(
                  child: sel == null
                      ? _grid()
                      : _SpeciesList(
                          category: sel,
                          onPick: _pickSpecies,
                          onNarrateNearby: _narrateNearby,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bar(_Cat? sel) => Padding(
        padding: const EdgeInsets.fromLTRB(RD.sm, RD.sm, RD.lg, RD.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: RD.textPrimary),
                onPressed: () {
                  if (sel != null) {
                    setState(() => _selected = null);
                  } else {
                    Navigator.of(context).maybePop();
                  }
                },
              ),
              Expanded(
                child: Text(sel?.label ?? 'I See Something',
                    style: RD.title.copyWith(fontSize: 22)),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(RD.md, 0, 0, RD.sm),
              child: Text(
                sel == null
                    ? "What caught your eye? Pick a category to see what's around you."
                    : 'Tap one to hear its story on the radio.',
                style: RD.body,
              ),
            ),
          ],
        ),
      );

  Widget _grid() => GridView.count(
        padding: const EdgeInsets.all(RD.lg),
        crossAxisCount: 3,
        mainAxisSpacing: RD.md,
        crossAxisSpacing: RD.md,
        childAspectRatio: 0.95,
        children: [
          for (final c in _categories)
            CategoryTile(
              icon: c.icon,
              label: c.label,
              onTap: () => setState(() => _selected = c),
            ),
        ],
      );
}

/// The species documented for a category, each with a photo + name; tapping
/// narrates it. Falls back to a "what's around me" nearby narration when the
/// category has no catalogued species yet.
class _SpeciesList extends ConsumerWidget {
  const _SpeciesList({
    required this.category,
    required this.onPick,
    required this.onNarrateNearby,
  });
  final _Cat category;
  final void Function(Species) onPick;
  final VoidCallback onNarrateNearby;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(speciesByCategoryProvider(category.token));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(color: RD.green)),
      error: (e, _) => _fallback(context,
          'Couldn\'t load ${category.label.toLowerCase()}.'),
      data: (species) {
        if (species.isEmpty) {
          return _fallback(context,
              'No catalogued ${category.label.toLowerCase()} yet.');
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(RD.lg, 0, RD.lg, RD.xl),
          itemCount: species.length,
          separatorBuilder: (_, _) => const SizedBox(height: RD.md),
          itemBuilder: (_, i) {
            final s = species[i];
            return LocationCard(
              title: s.commonName,
              subtitle: (s.scientificName ?? '').isNotEmpty
                  ? s.scientificName!
                  : (s.description ?? category.label),
              imageUrl: _imageUrl(s),
              leadingIcon: category.icon,
              trailing: const Icon(Icons.play_circle_fill_rounded,
                  color: RD.green),
              onTap: () => onPick(s),
            );
          },
        );
      },
    );
  }

  /// Resolves a species photo to a loadable URL. `hero_image` may be a full URL
  /// or a relative storage path (e.g. `wildlife/…jpg`) — the latter is resolved
  /// against the public `media` bucket. A bad/missing path just falls back to
  /// the category icon (LocationCard never shows a broken image).
  String? _imageUrl(Species s) {
    final raw = s.heroImageUrl;
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http')) return raw;
    try {
      return SupabaseService.client.storage.from('media').getPublicUrl(raw);
    } catch (_) {
      return null;
    }
  }

  Widget _fallback(BuildContext context, String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(RD.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(category.icon, size: 44, color: RD.greenDim),
              const SizedBox(height: RD.md),
              Text(message, textAlign: TextAlign.center, style: RD.body),
              const SizedBox(height: RD.lg),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: RD.green, foregroundColor: RD.onGreen),
                onPressed: onNarrateNearby,
                icon: const Icon(Icons.my_location_rounded),
                label: const Text("Tell me what's around me"),
              ),
            ],
          ),
        ),
      );
}
