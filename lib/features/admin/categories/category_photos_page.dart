import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/admin/categories/category_image_picker.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/shared/design/category_fallback_image_repository.dart';
import 'package:explorer_os_mobile/shared/design/category_visuals.dart';

/// Admin -> Category Photos: assigns a real photograph to each Discover
/// category-visual bucket (Festivals, Springs, Food, Nightlife, ...) so a
/// card without its own photo shows something more specific than the
/// icon+color tile. Every bucket always has a usable fallback regardless —
/// this page is purely additive polish, never required for Discover to work.
class CategoryPhotosPage extends ConsumerWidget {
  const CategoryPhotosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photosAsync = ref.watch(categoryFallbackImagesProvider);
    final photos = photosAsync.value ?? const {};

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AdminPageHeader(
          title: 'Category Photos',
          subtitle: 'A real photograph for each Discover category — used whenever an '
              'individual item has no photo of its own. The vivid icon+color tile is '
              'still the fallback for any category left unassigned here.',
        ),
        const SizedBox(height: 16),
        if (photosAsync.isLoading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          for (final key in categoryVisualKeys) _row(context, ref, key, photos[key]),
      ],
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, String key, String? photoUrl) {
    final label = _labelFor(key);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 56,
            height: 56,
            child: CategoryImagePlaceholder(label, iconSize: 26, categoryPhotoUrl: photoUrl),
          ),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(photoUrl == null ? 'Using icon+color fallback' : 'Custom photo assigned'),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            switch (v) {
              case 'find':
                await showCategoryImagePicker(context, categoryKey: key, categoryLabel: label);
              case 'clear':
                await ref.read(categoryFallbackImageRepositoryProvider).clear(key);
                ref.read(categoryFallbackImagesRefreshProvider.notifier).bump();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'find', child: Text('Find photo')),
            if (photoUrl != null)
              const PopupMenuItem(value: 'clear', child: Text('Remove photo')),
          ],
        ),
        onTap: () => showCategoryImagePicker(context, categoryKey: key, categoryLabel: label),
      ),
    );
  }

  /// A readable label for a canonical bucket key — the picker's default
  /// search query and this page's display text only; never written anywhere.
  String _labelFor(String key) => switch (key) {
        'gems' => 'Gems',
        'food' => 'Food',
        'markets' => 'Markets',
        'shopping' => 'Shopping',
        'festivals' => 'Festivals',
        'springs' => 'Springs',
        'waterfalls' => 'Waterfalls',
        'parks' => 'Parks',
        'forests' => 'Forests',
        'trails' => 'Trails',
        'birds' => 'Birds',
        'wildlife' => 'Wildlife',
        'plants' => 'Plants & Wildflowers',
        'museums' => 'Museums',
        'history' => 'History',
        'theater' => 'Theater',
        'arts_culture' => 'Arts & Culture',
        'live_music' => 'Live Music',
        'equestrian' => 'Horses & Equestrian',
        'cars_trucks' => 'Cars & Trucks',
        'kids' => 'Kids',
        'family' => 'Family',
        'fishing' => 'Fishing',
        'boating' => 'Boating',
        'photography' => 'Photography',
        'bars' => 'Bars',
        'nightlife' => 'Nightlife',
        'adventure' => 'Adventure',
        'camping' => 'Camping',
        'swimming' => 'Swimming',
        'scenic' => 'Scenic Views',
        'lodging' => 'Lodging',
        'free' => 'Free Things',
        'caves' => 'Caves',
        'beaches' => 'Beaches',
        'water' => 'Lakes & Rivers',
        'events' => 'Events',
        'outdoors' => 'Outdoors',
        'attractions' => 'Attractions',
        _ => key,
      };
}
