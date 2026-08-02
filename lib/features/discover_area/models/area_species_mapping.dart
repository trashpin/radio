/// Maps a Discover This Area category token to the `species.category` values
/// it should pull from. Reuses the existing Species catalog entirely — no
/// new species data model, just a different grouping of what's already
/// there for the area-discovery context.
const Map<String, List<String>> areaSpeciesCategoryMap = {
  // Spec: "Learn about: Mammals, Reptiles, Amphibians, Fish, Insects".
  'wildlife': ['animals', 'reptiles', 'amphibians', 'fish', 'insects'],
  'birds': ['birds'],
  // Spec: "Learn about: Native plants, Wildflowers, Trees, Protected species".
  'plants_trees': ['trees', 'plants', 'wildflowers'],
};
