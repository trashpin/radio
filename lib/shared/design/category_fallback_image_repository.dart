import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';

/// Read/write access to `category_fallback_images` (migration 0059) — an
/// admin-assigned real photograph per category-visual bucket (see
/// `category_visuals.dart`'s [categoryVisualKeyFor]). Read-safe: returns an
/// empty map when Supabase isn't configured or the table doesn't exist yet,
/// so a missing/pending migration just means every category keeps showing
/// its icon+gradient tile rather than erroring.
class CategoryFallbackImageRepository {
  const CategoryFallbackImageRepository();

  Future<Map<String, String>> all() async {
    if (!SupabaseService.isConfigured) return const {};
    try {
      final rows = await SupabaseService.client
          .from('category_fallback_images')
          .select() as List;
      return {
        for (final r in rows.cast<Map<String, dynamic>>())
          (r['category_key'] ?? '').toString(): (r['image_url'] ?? '').toString(),
      }..removeWhere((k, v) => k.isEmpty || v.isEmpty);
    } catch (_) {
      return const {};
    }
  }

  Future<void> set(String categoryKey, String imageUrl) async {
    await SupabaseService.client.from('category_fallback_images').upsert({
      'category_key': categoryKey,
      'image_url': imageUrl,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> clear(String categoryKey) async {
    await SupabaseService.client
        .from('category_fallback_images')
        .delete()
        .eq('category_key', categoryKey);
  }
}

final categoryFallbackImageRepositoryProvider =
    Provider<CategoryFallbackImageRepository>((ref) => const CategoryFallbackImageRepository());

class CategoryFallbackImagesRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final categoryFallbackImagesRefreshProvider =
    NotifierProvider<CategoryFallbackImagesRefresh, int>(CategoryFallbackImagesRefresh.new);

/// `category_key -> image_url` for every category with an assigned photo.
/// Discover/Explore cards watch this and pass the resolved URL into
/// `CategoryImagePlaceholder`.
final categoryFallbackImagesProvider = FutureProvider<Map<String, String>>((ref) {
  ref.watch(categoryFallbackImagesRefreshProvider);
  return ref.watch(categoryFallbackImageRepositoryProvider).all();
});
