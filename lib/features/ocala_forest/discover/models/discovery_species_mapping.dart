import 'package:explorer_os_mobile/features/ocala_forest/discover/models/discovery_category.dart';

/// Maps a DISCOVER group/subtype to the `species.category` values worth
/// checking for a KNOWN match (spec follow-up: "show them a pic of known
/// info on these categories first — if there isn't one that matches what
/// they're seeing, then they can take a photo"). Best-effort and coarse on
/// purpose: an empty result just means this subtype has no existing
/// reference content, and the capture flow falls straight through to the
/// photo step exactly as before — this never blocks anything, it only
/// offers a shortcut when a real match already exists.
List<String> speciesCategoriesFor(DiscoveryGroup group, String? subtype) {
  switch (group) {
    case DiscoveryGroup.wildlife:
      switch (subtype) {
        case 'Tracks/Signs':
          return const ['animal_tracks'];
        case 'Reptile':
          return const ['reptiles'];
        case 'Amphibian':
          return const ['amphibians'];
        case 'Insect':
          return const ['insects'];
        case 'Animal':
        default:
          return const ['mammals', 'fish'];
      }
    case DiscoveryGroup.birds:
      return const ['birds'];
    case DiscoveryGroup.plantsNature:
      switch (subtype) {
        case 'Tree':
          return const ['trees'];
        case 'Plant':
          return const ['plants'];
        case 'Flower':
        case 'Wildflower':
          return const ['wildflowers'];
        case 'Mushroom':
          return const ['mushrooms'];
        case 'Interesting Natural Feature':
          return const ['scenic_views', 'trail_features'];
        default:
          return const ['plants', 'trees', 'wildflowers', 'mushrooms'];
      }
    case DiscoveryGroup.water:
      return const ['springs', 'waterfalls'];
    case DiscoveryGroup.geology:
      return const []; // no matching species category exists yet
    case DiscoveryGroup.history:
      return const ['historic_sites'];
    case DiscoveryGroup.other:
      return const [];
  }
}
