/// Pure category inference for map markers — no Flutter imports so it can be
/// reused by both the app (marker colors) and the server-side data tool that
/// backfills `map_locations.category`.
///
/// Buckets a POI into one of the Map Editor legend categories by first honoring
/// an explicit legend token, then scanning the category/subcategory/name text
/// for keywords. Falls back to 'other'. Order is priority (first match wins).
library;

/// The legend category keys, matching the Map Editor + `MarkerCategoryStyle`.
const markerCategoryKeys = <String>[
  'trailheads',
  'visitor_centers',
  'historic_sites',
  'wildlife_viewing',
  'safety_alerts',
  'campgrounds',
  'parking',
  'springs',
  'scenic_overlooks',
  'cities',
  'other',
];

/// Words that mark a park / natural area (kept as 'other', never 'cities').
const _parkWords = <String>[
  'state park',
  'national park',
  'state reserve',
  'state forest',
  'national forest',
  'recreation area',
  'archaeological',
  'botanical',
  'hammock',
  'wilderness',
  'wildlife management',
  'scrub',
  'reserve',
  ' park',
  ' forest',
];

/// (keyword, legend key) rules in priority order. Specific facilities beat
/// generic scenery/water so e.g. "Juniper Springs Campground" -> campgrounds.
const _rules = <(String, String)>[
  ('safety', 'safety_alerts'),
  ('hazard', 'safety_alerts'),
  ('warning', 'safety_alerts'),
  ('danger', 'safety_alerts'),
  ('alert', 'safety_alerts'),
  ('flood', 'safety_alerts'),
  ('closed', 'safety_alerts'),
  ('campground', 'campgrounds'),
  ('campsite', 'campgrounds'),
  ('camping', 'campgrounds'),
  ('camp ', 'campgrounds'),
  ('rv park', 'campgrounds'),
  ('visitor center', 'visitor_centers'),
  ('visitor centre', 'visitor_centers'),
  ('welcome center', 'visitor_centers'),
  ('information center', 'visitor_centers'),
  ('ranger', 'visitor_centers'),
  ('trailhead', 'trailheads'),
  ('trail head', 'trailheads'),
  ('ohv', 'trailheads'),
  ('trail', 'trailheads'),
  ('historic', 'historic_sites'),
  ('heritage', 'historic_sites'),
  ('fort ', 'historic_sites'),
  ('lighthouse', 'historic_sites'),
  ('battlefield', 'historic_sites'),
  ('monument', 'historic_sites'),
  ('museum', 'historic_sites'),
  ('ruins', 'historic_sites'),
  ('cemetery', 'historic_sites'),
  ('overlook', 'scenic_overlooks'),
  ('scenic', 'scenic_overlooks'),
  ('vista', 'scenic_overlooks'),
  ('viewpoint', 'scenic_overlooks'),
  ('lookout', 'scenic_overlooks'),
  ('beach', 'scenic_overlooks'),
  ('coastal', 'scenic_overlooks'),
  ('island', 'scenic_overlooks'),
  ('shore', 'scenic_overlooks'),
  ('parking', 'parking'),
  ('wildlife', 'wildlife_viewing'),
  ('rookery', 'wildlife_viewing'),
  ('refuge', 'wildlife_viewing'),
  ('preserve', 'wildlife_viewing'),
  ('sanctuary', 'wildlife_viewing'),
  ('bird', 'wildlife_viewing'),
  ('spring', 'springs'),
];

/// Exact legend tokens (already-categorized rows keep their category).
const _exactTokens = <String, String>{
  'trailheads': 'trailheads',
  'trailhead': 'trailheads',
  'trails': 'trailheads',
  'visitor_centers': 'visitor_centers',
  'visitor_center': 'visitor_centers',
  'ranger_stations': 'visitor_centers',
  'cities': 'cities',
  'city': 'cities',
  'town': 'cities',
  'historic_sites': 'historic_sites',
  'historic_site': 'historic_sites',
  'wildlife_viewing': 'wildlife_viewing',
  'wildlife': 'wildlife_viewing',
  'safety_alerts': 'safety_alerts',
  'campgrounds': 'campgrounds',
  'campground': 'campgrounds',
  'parking': 'parking',
  'springs': 'springs',
  'spring': 'springs',
  'scenic_overlooks': 'scenic_overlooks',
  'scenic_overlook': 'scenic_overlooks',
};

/// Infers a legend category key from an explicit [category] plus free text
/// ([name], [subcategory]). Returns one of [markerCategoryKeys].
String inferCategoryKey(String? category, String? name, [String? subcategory]) {
  final cat = (category ?? '').toLowerCase().trim();
  final exact = _exactTokens[cat];
  if (exact != null) return exact;

  final text = [category, subcategory, name]
      .where((s) => s != null && s.trim().isNotEmpty)
      .join(' ')
      .toLowerCase();
  if (text.trim().isEmpty) return 'other';
  for (final (keyword, key) in _rules) {
    if (text.contains(keyword)) return key;
  }
  // No feature keyword. Parks/natural areas stay 'other'; a bare place name
  // (e.g. "Ocala", "Dunnellon") is treated as a city.
  for (final w in _parkWords) {
    if (text.contains(w)) return 'other';
  }
  return 'cities';
}
