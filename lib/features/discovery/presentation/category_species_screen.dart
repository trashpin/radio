import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/discovery/data/species_repository.dart';
import 'package:explorer_os_mobile/features/discovery/models/discovery_category.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';

/// Species list for one discovery category (e.g. Plants). Reads the master
/// `species` table from Supabase; search filters the loaded list.
class CategorySpeciesScreen extends ConsumerStatefulWidget {
  const CategorySpeciesScreen({super.key, required this.category});
  final DiscoveryCategory category;

  @override
  ConsumerState<CategorySpeciesScreen> createState() =>
      _CategorySpeciesScreenState();
}

class _CategorySpeciesScreenState extends ConsumerState<CategorySpeciesScreen> {
  static const Color _bg = Color(0xFF0B120E);
  static const Color _card = Color(0xFF161E19);
  static const Color _accent = Color(0xFFEE7B2E);
  static const Color _textPrimary = Color(0xFFF3F6F2);
  static const Color _textSecondary = Color(0xFF8E9A93);

  String _query = '';
  final _favorites = <String>{};

  List<Species> _filter(List<Species> all) {
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all
        .where((s) =>
            s.commonName.toLowerCase().contains(q) ||
            (s.scientificName?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(speciesByCategoryProvider(widget.category.token));
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _textPrimary,
        title: Text(widget.category.label,
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  style: const TextStyle(color: _textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search ${widget.category.label.toLowerCase()}…',
                    hintStyle: const TextStyle(color: _textSecondary),
                    prefixIcon:
                        const Icon(Icons.search_rounded, color: _textSecondary),
                    filled: true,
                    fillColor: _card,
                    border: OutlineInputBorder(
                      borderRadius: AppRadius.pillAll,
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              Expanded(
                child: async.when(
                  loading: () => const Center(
                      child: CircularProgressIndicator(color: _accent)),
                  error: (e, _) => _empty(
                    'Could not load ${widget.category.label.toLowerCase()}.\n'
                    'Run migration 0004_species.sql and import via Base44.',
                    Icons.cloud_off_rounded,
                  ),
                  data: (all) {
                    final rows = _filter(all);
                    if (rows.isEmpty) {
                      return _empty(
                        _query.isEmpty
                            ? 'No ${widget.category.label.toLowerCase()} yet.\n'
                                'Import them in Base44 to populate this guide.'
                            : 'No matches for "$_query".',
                        widget.category.icon,
                      );
                    }
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        mainAxisSpacing: AppSpacing.md,
                        crossAxisSpacing: AppSpacing.md,
                        childAspectRatio: 0.78,
                      ),
                      itemCount: rows.length,
                      itemBuilder: (context, i) =>
                          _speciesCard(rows[i]),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(String message, IconData icon) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _textSecondary, size: 44),
            const Gap.v(AppSpacing.md),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _textSecondary)),
          ],
        ),
      );

  Widget _speciesCard(Species s) {
    final fav = _favorites.contains(s.id);
    final img = s.heroImageUrl;
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: AppRadius.lgAll,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (img != null && img.isNotEmpty)
                  Image.network(img, fit: BoxFit.cover)
                else
                  Container(
                    color: widget.category.color.withValues(alpha: 0.25),
                    child: Icon(widget.category.icon,
                        color: widget.category.color, size: 40),
                  ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: InkWell(
                    onTap: () => setState(() =>
                        fav ? _favorites.remove(s.id) : _favorites.add(s.id)),
                    child: CircleAvatar(
                      radius: 15,
                      backgroundColor: Colors.black45,
                      child: Icon(
                        fav
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: fav ? _accent : Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.commonName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: _textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                      if (s.scientificName != null)
                        Text(s.scientificName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: _textSecondary,
                                fontSize: 11,
                                fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Quick Listen — narration coming soon')),
                  ),
                  child: const Icon(Icons.volume_up_rounded,
                      color: _accent, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
