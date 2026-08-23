/// DISCOVER's category taxonomy (spec §2) — the top-level group a visitor
/// picks first, plus a free-text subtype within it. Kept as a plain enum +
/// string list (not a rigid per-subtype enum) since the exact subtype is
/// descriptive metadata, not something other code branches on — matching
/// how `forest_trail_segments` stores many official-but-unbranched fields
/// as plain text.
enum DiscoveryGroup {
  wildlife('wildlife', 'Wildlife', '🐾'),
  birds('birds', 'Birds', '🐦'),
  plantsNature('plants_nature', 'Plants & Nature', '🌿'),
  water('water', 'Water', '💧'),
  geology('geology', 'Geology', '🪨'),
  history('history', 'History', '📜'),
  other('other', 'Something Else', '👀');

  const DiscoveryGroup(this.id, this.label, this.emoji);

  final String id;
  final String label;
  final String emoji;

  static DiscoveryGroup? fromId(String? id) {
    for (final g in DiscoveryGroup.values) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// Best-effort mapping from the app-wide `species.category` taxonomy
  /// (`lib/features/discovery/models/species.dart`) to DISCOVER's own
  /// category tree — used only to pick a sensible starting group when
  /// linking from an existing wildlife page's "Report a Discovery" button
  /// (spec §12). Never skips the photo/AI-suggestion flow itself.
  static DiscoveryGroup fromSpeciesCategory(String category) {
    switch (category) {
      case 'birds':
        return DiscoveryGroup.birds;
      case 'mammals':
      case 'reptiles':
      case 'amphibians':
      case 'insects':
      case 'fish':
      case 'animal_tracks':
        return DiscoveryGroup.wildlife;
      case 'plants':
      case 'trees':
      case 'mushrooms':
      case 'wildflowers':
        return DiscoveryGroup.plantsNature;
      case 'springs':
      case 'waterfalls':
        return DiscoveryGroup.water;
      case 'historic_sites':
        return DiscoveryGroup.history;
      case 'scenic_views':
      case 'trail_features':
        return DiscoveryGroup.plantsNature;
      default:
        return DiscoveryGroup.other;
    }
  }

  /// The subtype choices shown once this group is picked (spec §2). Free
  /// text on save — this list only drives the picker UI, it's never a DB
  /// enum, so a subtype outside this list (typed via "Something Else")
  /// still saves cleanly.
  List<String> get subtypes {
    switch (this) {
      case DiscoveryGroup.wildlife:
        return const ['Animal', 'Tracks/Signs', 'Reptile', 'Amphibian', 'Insect'];
      case DiscoveryGroup.birds:
        return const ['Bird', 'Other Bird-Related Discovery'];
      case DiscoveryGroup.plantsNature:
        return const [
          'Tree',
          'Plant',
          'Flower',
          'Wildflower',
          'Mushroom',
          'Interesting Natural Feature',
        ];
      case DiscoveryGroup.water:
        return const ['Spring', 'Lake', 'Creek', 'Water Feature', 'Sinkhole'];
      case DiscoveryGroup.geology:
        return const ['Rock', 'Formation', 'Terrain', 'Geological Feature'];
      case DiscoveryGroup.history:
        return const [
          'Historic Location',
          'Historic Structure',
          'Historical Feature',
          'Archaeological/Historical Discovery',
        ];
      case DiscoveryGroup.other:
        return const [];
    }
  }
}
