/// Holds listener preferences that influence the engine's decisions.
///
/// WHY THIS EXISTS: the engine should respect what the listener wants — e.g.
/// muting ambient audio, reducing narration frequency, or muting certain tags.
/// Centralizing preferences means every scheduler/decision can consult one
/// place. In-memory now; will be backed by persisted/synced settings later.
class UserPreferenceManager {
  UserPreferenceManager({
    this.narrationsEnabled = true,
    this.announcementsEnabled = true,
    this.ambientEnabled = true,
    Set<String>? mutedTags,
    this.preferredStationId,
  }) : mutedTags = mutedTags ?? <String>{};

  bool narrationsEnabled;
  bool announcementsEnabled;
  bool ambientEnabled;
  final Set<String> mutedTags;
  String? preferredStationId;

  /// Whether a segment with the given [tags] is allowed given muted tags.
  bool allowsTags(List<String> tags) => !tags.any(mutedTags.contains);
}
