import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/discovery/data/species_repository.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';
import 'package:explorer_os_mobile/features/radio/discovery/observation_controller.dart';

/// Forest palette for the discovery experience.
class _Forest {
  static const bg = Color(0xFF0B120E);
  static const card = Color(0xFF17231B);
  static const card2 = Color(0xFF1E2E23);
  static const accent = Color(0xFF8Fc46B);
  static const text = Color(0xFFF3F6F2);
  static const textDim = Color(0xFF9DB0A2);
}

/// A discovery category on the "I See Something" grid.
class _Cat {
  const _Cat(this.label, this.emoji, this.token);
  final String label;
  final String emoji;
  final String token; // maps to species.category
}

const _cats = <_Cat>[
  _Cat('Animals', '🐻', 'animals'),
  _Cat('Birds', '🦅', 'birds'),
  _Cat('Wildflowers', '🌼', 'wildflowers'),
  _Cat('Plants', '🌿', 'plants'),
  _Cat('Trees', '🌳', 'trees'),
  _Cat('Mushrooms', '🍄', 'mushrooms'),
  _Cat('Butterflies', '🦋', 'insects'),
  _Cat('Reptiles', '🐍', 'reptiles'),
  _Cat('Amphibians', '🐢', 'amphibians'),
  _Cat('Fish', '🐟', 'fish'),
  _Cat('Rocks & Geology', '🪨', 'geology'),
  _Cat('Animal Tracks', '🐾', 'animal_tracks'),
  _Cat('Insects', '🕸️', 'insects'),
  _Cat('Night Sky', '🌌', 'scenic_views'),
  _Cat('Historic Structures', '🏕️', 'historic_sites'),
  _Cat('Waterways', '🚣', 'springs'),
];

/// Opens the full-screen "I See Something" flow. On selecting a species it
/// starts the observation (ducks music + narrates) and returns to the radio.
Future<void> showISeeSomething(BuildContext context, WidgetRef ref) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => const _ISeeSomethingScreen(),
  ));
}

class _ISeeSomethingScreen extends ConsumerStatefulWidget {
  const _ISeeSomethingScreen();
  @override
  ConsumerState<_ISeeSomethingScreen> createState() => _ISeeState();
}

class _ISeeState extends ConsumerState<_ISeeSomethingScreen> {
  _Cat? _selected;

  void _pick(Species s) {
    ref.read(observationControllerProvider.notifier).observe(s);
    Navigator.of(context).pop(); // back to radio; narration starts
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Forest.bg,
      appBar: AppBar(
        backgroundColor: _Forest.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _Forest.text,
        leading: _selected != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() => _selected = null))
            : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_selected?.label.toUpperCase() ?? 'I SEE SOMETHING',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800)),
            Text(_selected == null ? 'What caught your attention?' : 'Tap to learn',
                style: const TextStyle(
                    fontSize: 12,
                    color: _Forest.textDim,
                    fontWeight: FontWeight.w400)),
          ],
        ),
      ),
      body: _selected == null ? _grid() : _SpeciesList(cat: _selected!, onPick: _pick),
    );
  }

  Widget _grid() {
    return GridView.count(
      padding: const EdgeInsets.all(16),
      crossAxisCount: 2,
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childAspectRatio: 1.4,
      children: [
        for (final c in _cats)
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => _selected = c),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_Forest.card2, _Forest.card],
                ),
                border: Border.all(
                    color: _Forest.accent.withValues(alpha: 0.18)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(c.emoji, style: const TextStyle(fontSize: 38)),
                  const SizedBox(height: 8),
                  Text(c.label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: _Forest.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _SpeciesList extends ConsumerStatefulWidget {
  const _SpeciesList({required this.cat, required this.onPick});
  final _Cat cat;
  final void Function(Species) onPick;
  @override
  ConsumerState<_SpeciesList> createState() => _SpeciesListState();
}

class _SpeciesListState extends ConsumerState<_SpeciesList> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(speciesByCategoryProvider(widget.cat.token));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            autofocus: true,
            style: const TextStyle(color: _Forest.text),
            onChanged: (v) => setState(() => _q = v.toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Search ${widget.cat.label.toLowerCase()}…',
              hintStyle: const TextStyle(color: _Forest.textDim),
              prefixIcon: const Icon(Icons.search_rounded, color: _Forest.textDim),
              filled: true,
              fillColor: _Forest.card,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: async.when(
            loading: () =>
                const Center(child: CircularProgressIndicator(color: _Forest.accent)),
            error: (e, _) => Center(
                child: Text('Could not load.\n$e',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _Forest.textDim))),
            data: (all) {
              final rows = all
                  .where((s) =>
                      _q.isEmpty || s.commonName.toLowerCase().contains(_q))
                  .toList();
              if (rows.isEmpty) {
                return Center(
                    child: Text('No ${widget.cat.label.toLowerCase()} found.',
                        style: const TextStyle(color: _Forest.textDim)));
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: rows.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final s = rows[i];
                  return Material(
                    color: _Forest.card,
                    borderRadius: BorderRadius.circular(14),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: (s.heroImageUrl != null)
                            ? Image.network(s.heroImageUrl!,
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, st) => const SizedBox(
                                    width: 52,
                                    height: 52,
                                    child: Icon(Icons.eco_rounded,
                                        color: _Forest.accent)))
                            : Container(
                                width: 52,
                                height: 52,
                                color: _Forest.card2,
                                child: const Icon(Icons.eco_rounded,
                                    color: _Forest.accent)),
                      ),
                      title: Text(s.commonName,
                          style: const TextStyle(
                              color: _Forest.text,
                              fontWeight: FontWeight.w600)),
                      subtitle: s.scientificName != null
                          ? Text(s.scientificName!,
                              style: const TextStyle(
                                  color: _Forest.textDim,
                                  fontStyle: FontStyle.italic))
                          : null,
                      trailing: const Icon(Icons.play_circle_fill_rounded,
                          color: _Forest.accent),
                      onTap: () => widget.onPick(s),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
