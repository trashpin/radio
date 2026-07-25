/// A content category that can have a default narration voice assigned.
/// [token] is the stable id stored in `voice_assignments.category`.
class NarrationCategory {
  const NarrationCategory(this.token, this.label);
  final String token;
  final String label;
}

/// The assignable narration categories (per the Voice Manager spec).
const narrationCategories = <NarrationCategory>[
  NarrationCategory('wildlife', 'Wildlife'),
  NarrationCategory('birds', 'Birds'),
  NarrationCategory('fish', 'Fish'),
  NarrationCategory('plants', 'Plants'),
  NarrationCategory('trees', 'Trees'),
  NarrationCategory('trails', 'Trails'),
  NarrationCategory('historic_sites', 'Historic Sites'),
  NarrationCategory('springs', 'Springs'),
  NarrationCategory('campgrounds', 'Campgrounds'),
  NarrationCategory('kids_mode', 'Kids Mode'),
  NarrationCategory('safety_messages', 'Safety Messages'),
  NarrationCategory('explorer_radio', 'Explorer Radio'),
];
