import 'package:flutter/material.dart';

import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/discovery/models/discovery_category.dart';
import 'package:explorer_os_mobile/features/discovery/presentation/category_species_screen.dart';

/// The WILDLIFE GUIDE tab — browse and listen to the existing wildlife,
/// nature, and history categories over the master `species` catalog (the
/// same content the "I See Something" identification flow reads). This
/// screen is a plain browse/listen guide, not an identification or
/// reporting tool: picking a category opens [CategorySpeciesScreen] (search
/// + grid over real Supabase species), and picking a species opens its
/// existing detail page with narration/text-to-speech. No new data source,
/// no observation/sighting logging.
class WildlifeScreen extends StatelessWidget {
  const WildlifeScreen({super.key});

  static const Color _bg = Color(0xFF0B120E);
  static const Color _card = Color(0xFF161E19);
  static const Color _textPrimary = Color(0xFFF3F6F2);
  static const Color _textSecondary = Color(0xFF8E9A93);

  /// The six categories the Wildlife Guide shows — UI-only trim over the
  /// shared [discoveryCategories] list (used unfiltered elsewhere, e.g. "I
  /// See Something"). Every other category (nature/history/etc.) still
  /// exists in the data and is still reachable from that other flow; it's
  /// just not shown as a tile here.
  static const _kWildlifeGuideTokens = {
    'animals', 'birds', 'reptiles', 'amphibians', 'fish', 'plants',
  };

  static final _categories = discoveryCategories
      .where((c) => _kWildlifeGuideTokens.contains(c.token))
      .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _textPrimary,
        elevation: 0,
        title: const Text('Wildlife Guide',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
            children: [
              const Text(
                'Browse and listen to Marion County wildlife — tap a '
                'category, then a species to hear its story.',
                style: TextStyle(color: _textSecondary, fontSize: 13),
              ),
              const Gap.v(AppSpacing.lg),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpacing.md,
                crossAxisSpacing: AppSpacing.md,
                childAspectRatio: 0.86,
                children: [
                  for (final c in _categories)
                    _CategoryCard(
                      category: c,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CategorySpeciesScreen(category: c),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.onTap});

  final DiscoveryCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WildlifeScreen._card,
      borderRadius: AppRadius.lgAll,
      child: InkWell(
        borderRadius: AppRadius.lgAll,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: category.color.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(category.icon, color: category.color, size: 28),
              ),
              const Gap.v(AppSpacing.sm),
              Text(category.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: WildlifeScreen._textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(category.subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: WildlifeScreen._textSecondary,
                      fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}
