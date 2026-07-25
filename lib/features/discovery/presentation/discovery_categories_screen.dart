import 'package:flutter/material.dart';

import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/discovery/models/discovery_category.dart';

/// 👀 I See Something — the Discovery Categories screen.
///
/// A dark, premium grid of category cards (Animals, Birds, … , I Don't Know)
/// plus a "Popular in This Park" row. Tapping a category opens its guide
/// (species list) — currently a placeholder pending the next screen's design.
class DiscoveryCategoriesScreen extends StatelessWidget {
  const DiscoveryCategoriesScreen({super.key});

  static const Color _bg = Color(0xFF0B120E);
  static const Color _card = Color(0xFF161E19);
  static const Color _accent = Color(0xFFEE7B2E);
  static const Color _textPrimary = Color(0xFFF3F6F2);
  static const Color _textSecondary = Color(0xFF8E9A93);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _textPrimary,
        elevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl),
            children: [
              Column(
                children: const [
                  Icon(Icons.travel_explore_rounded, color: _accent, size: 40),
                  Gap.v(AppSpacing.sm),
                  Text('I SEE SOMETHING',
                      style: TextStyle(
                          color: _textPrimary,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5)),
                  Gap.v(AppSpacing.xs),
                  Text('What would you like to identify?',
                      style: TextStyle(
                          color: _textSecondary, fontSize: 14)),
                ],
              ),
              const Gap.v(AppSpacing.xl),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpacing.md,
                crossAxisSpacing: AppSpacing.md,
                childAspectRatio: 0.86,
                children: [
                  for (final c in discoveryCategories)
                    _CategoryCard(
                      category: c,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => _CategoryPlaceholder(category: c),
                        ),
                      ),
                    ),
                ],
              ),
              const Gap.v(AppSpacing.xl),
              const _PopularInPark(),
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
      color: DiscoveryCategoriesScreen._card,
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
                      color: DiscoveryCategoriesScreen._textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(category.subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: DiscoveryCategoriesScreen._textSecondary,
                      fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Popular in This Park" — a horizontal row of common species. Curated demo
/// data for now; wired to Supabase (park species) in a later step.
class _PopularInPark extends StatelessWidget {
  const _PopularInPark();

  static const _popular = [
    ('Black Bear', 'https://images.unsplash.com/photo-1530595467537-0b5996c41f2d?w=200'),
    ('White-tailed Deer', 'https://images.unsplash.com/photo-1484406566174-9da000fda645?w=200'),
    ('Wild Turkey', 'https://images.unsplash.com/photo-1606580773819-49e1a7f2a3b3?w=200'),
    ('Red Maple', 'https://images.unsplash.com/photo-1507371341162-763b5e419408?w=200'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Popular in This Park',
                    style: TextStyle(
                        color: DiscoveryCategoriesScreen._accent,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                Text('Species commonly seen here',
                    style: TextStyle(
                        color: DiscoveryCategoriesScreen._textSecondary,
                        fontSize: 11)),
              ],
            ),
            const Row(
              children: [
                Text('See All',
                    style: TextStyle(
                        color: DiscoveryCategoriesScreen._accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                Icon(Icons.chevron_right_rounded,
                    color: DiscoveryCategoriesScreen._accent, size: 18),
              ],
            ),
          ],
        ),
        const Gap.v(AppSpacing.md),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _popular.length,
            separatorBuilder: (_, _) => const Gap.h(AppSpacing.lg),
            itemBuilder: (context, i) {
              final (name, url) = _popular[i];
              return SizedBox(
                width: 72,
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: DiscoveryCategoriesScreen._card,
                      backgroundImage: NetworkImage(url),
                    ),
                    const Gap.v(AppSpacing.xs),
                    Text(name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: DiscoveryCategoriesScreen._textPrimary,
                            fontSize: 11)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Placeholder for a category's species list (next screen to design/build).
class _CategoryPlaceholder extends StatelessWidget {
  const _CategoryPlaceholder({required this.category});
  final DiscoveryCategory category;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DiscoveryCategoriesScreen._bg,
      appBar: AppBar(
        backgroundColor: DiscoveryCategoriesScreen._bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: DiscoveryCategoriesScreen._textPrimary,
        title: Text(category.label),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: category.color.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(category.icon, color: category.color, size: 44),
            ),
            const Gap.v(AppSpacing.lg),
            Text('${category.label} guide',
                style: const TextStyle(
                    color: DiscoveryCategoriesScreen._textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
            const Gap.v(AppSpacing.sm),
            const Text('Species list, search, and detail pages coming next.',
                style:
                    TextStyle(color: DiscoveryCategoriesScreen._textSecondary)),
          ],
        ),
      ),
    );
  }
}
