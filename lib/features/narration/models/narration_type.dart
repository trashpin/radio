/// The editorial styles a narration can be written in. [id] is the stable
/// value stored in `narrations.narration_type`.
enum NarrationType {
  standardRanger('standard_ranger', 'Standard Ranger'),
  adventureGuide('adventure_guide', 'Adventure Guide'),
  familyGuide('family_guide', 'Family Guide'),
  kidsGuide('kids_guide', 'Kids Guide'),
  photographerTips('photographer_tips', 'Photographer Tips'),
  natureFacts('nature_facts', 'Nature Facts'),
  safetyInformation('safety_information', 'Safety Information'),
  deepDive('deep_dive', 'Deep Dive'),
  seasonal('seasonal', 'Seasonal');

  const NarrationType(this.id, this.label);
  final String id;
  final String label;

  static NarrationType fromId(String? id) => NarrationType.values.firstWhere(
        (t) => t.id == id,
        orElse: () => NarrationType.standardRanger,
      );
}
