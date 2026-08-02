import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

/// An admin-manageable location category (`public.categories`, migration
/// 0039). Seeded with every built-in [LocationType], but an admin can add
/// unlimited more — [slug] is what actually gets stored in
/// `locations.category` (always free text, never a foreign key).
class LocationCategory {
  const LocationCategory({
    required this.id,
    required this.slug,
    required this.label,
    this.icon,
    this.sortOrder = 0,
    this.active = true,
    this.updatedAt,
    this.createdAt,
  });

  final String id;
  final String slug;
  final String label;
  final String? icon;
  final int sortOrder;
  final bool active;
  final DateTime? updatedAt;
  final DateTime? createdAt;

  factory LocationCategory.fromJson(Map<String, dynamic> j) =>
      LocationCategory(
        id: (j['id'] ?? '').toString(),
        slug: (j['slug'] ?? '') as String,
        label: (j['label'] ?? '') as String,
        icon: j['icon'] as String?,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
        active: (j['active'] ?? true) as bool,
        updatedAt: DateTime.tryParse('${j['updated_at']}'),
        createdAt: DateTime.tryParse('${j['created_at']}'),
      );

  Map<String, dynamic> toWrite() => {
        'slug': slug,
        'label': label,
        'icon': icon,
        'sort_order': sortOrder,
        'active': active,
      };
}

/// A single option in a category picker — either a built-in [LocationType] or
/// an admin-added [LocationCategory], normalized to the same shape so the UI
/// doesn't need to care which.
class CategoryOption {
  const CategoryOption({
    required this.id,
    required this.label,
    this.isCustom = false,
  });

  /// The raw value stored in `locations.category`.
  final String id;
  final String label;

  /// True for admin-added categories not in the built-in [LocationType] enum.
  final bool isCustom;
}

/// Merges the built-in [LocationType] taxonomy with active admin-added
/// [custom] categories into one option list for pickers — built-ins first (in
/// their declared order), then any custom categories not already covered by a
/// built-in slug, sorted by [LocationCategory.sortOrder] then label.
///
/// Pure function — no I/O, easy to unit test independently of Supabase.
List<CategoryOption> combinedCategoryOptions(List<LocationCategory> custom) {
  final builtinIds = LocationType.values.map((t) => t.id).toSet();
  final options = [
    for (final t in LocationType.values)
      CategoryOption(id: t.id, label: t.label),
  ];

  final extra = custom
      .where((c) => c.active && !builtinIds.contains(c.slug))
      .toList()
    ..sort((a, b) {
      final bySort = a.sortOrder.compareTo(b.sortOrder);
      return bySort != 0 ? bySort : a.label.compareTo(b.label);
    });

  for (final c in extra) {
    options.add(CategoryOption(id: c.slug, label: c.label, isCustom: true));
  }
  return options;
}
