/// Topics the copilot tracks interest in — deliberately small and mapped
/// straight onto categories the app already has (location types, existing
/// content categories), not a new taxonomy.
enum CopilotTopic { history, springs, wildlife, museums, restaurants, events }

/// Best-effort mapping from an existing `LocationType.label` string to the
/// topic it should nudge — used both when learning from behavior (spec §6)
/// and when the brain decides how interesting a nearby place is. Returns
/// null for types that don't map to a tracked topic (still fine to mention,
/// just not profile-gated).
CopilotTopic? topicForTypeLabel(String? typeLabel) {
  final t = (typeLabel ?? '').toLowerCase();
  if (t.contains('spring')) return CopilotTopic.springs;
  if (t.contains('museum')) return CopilotTopic.museums;
  if (t.contains('restaurant') || t.contains('coffee')) {
    return CopilotTopic.restaurants;
  }
  if (t.contains('event') || t.contains('festival')) return CopilotTopic.events;
  if (t.contains('wildlife')) return CopilotTopic.wildlife;
  if (t.contains('historic') || t.contains('monument') || t.contains('memorial')) {
    return CopilotTopic.history;
  }
  return null;
}

enum InterestLevel { low, medium, high }

InterestLevel _raise(InterestLevel l) => switch (l) {
      InterestLevel.low => InterestLevel.medium,
      InterestLevel.medium => InterestLevel.high,
      InterestLevel.high => InterestLevel.high,
    };

InterestLevel _lower(InterestLevel l) => switch (l) {
      InterestLevel.high => InterestLevel.medium,
      InterestLevel.medium => InterestLevel.low,
      InterestLevel.low => InterestLevel.low,
    };

/// A lightweight, entirely local profile of what this traveler seems to
/// like — never sent anywhere except as short text hints in a `copilot-line`
/// prompt, never used to identify anyone, and fully visible/resettable by the
/// user (spec §6/§7: "learn preferences, not personal secrets").
class CopilotProfile {
  const CopilotProfile({
    this.interests = const {},
    this.sarcasm = InterestLevel.high,
    this.talkAmount = InterestLevel.medium,
    this.visitedPlaceIds = const {},
    this.discussedPlaceIds = const {},
    this.likedPlaceIds = const {},
    this.dislikedPlaceIds = const {},
  });

  final Map<CopilotTopic, InterestLevel> interests;
  final InterestLevel sarcasm;
  final InterestLevel talkAmount;
  final Set<String> visitedPlaceIds;
  final Set<String> discussedPlaceIds;
  final Set<String> likedPlaceIds;
  final Set<String> dislikedPlaceIds;

  static const empty = CopilotProfile();

  InterestLevel interestIn(CopilotTopic topic) =>
      interests[topic] ?? InterestLevel.medium;

  CopilotProfile copyWith({
    Map<CopilotTopic, InterestLevel>? interests,
    InterestLevel? sarcasm,
    InterestLevel? talkAmount,
    Set<String>? visitedPlaceIds,
    Set<String>? discussedPlaceIds,
    Set<String>? likedPlaceIds,
    Set<String>? dislikedPlaceIds,
  }) =>
      CopilotProfile(
        interests: interests ?? this.interests,
        sarcasm: sarcasm ?? this.sarcasm,
        talkAmount: talkAmount ?? this.talkAmount,
        visitedPlaceIds: visitedPlaceIds ?? this.visitedPlaceIds,
        discussedPlaceIds: discussedPlaceIds ?? this.discussedPlaceIds,
        likedPlaceIds: likedPlaceIds ?? this.likedPlaceIds,
        dislikedPlaceIds: dislikedPlaceIds ?? this.dislikedPlaceIds,
      );

  /// Gradual learning (spec §6): a full playthrough or "Tell Me More" tap
  /// nudges interest up; repeatedly skipping a topic nudges it down. Never a
  /// hard jump — interest moves one step at a time on a 3-level scale.
  CopilotProfile withTopicNudged(CopilotTopic topic, {required bool up}) {
    final current = interestIn(topic);
    final next = up ? _raise(current) : _lower(current);
    return copyWith(interests: {...interests, topic: next});
  }

  CopilotProfile withPlaceVisited(String placeId) =>
      copyWith(visitedPlaceIds: {...visitedPlaceIds, placeId});

  CopilotProfile withPlaceDiscussed(String placeId) =>
      copyWith(discussedPlaceIds: {...discussedPlaceIds, placeId});

  CopilotProfile withPlaceLiked(String placeId, {required bool liked}) => liked
      ? copyWith(
          likedPlaceIds: {...likedPlaceIds, placeId},
          dislikedPlaceIds: {...dislikedPlaceIds}..remove(placeId),
        )
      : copyWith(
          dislikedPlaceIds: {...dislikedPlaceIds, placeId},
          likedPlaceIds: {...likedPlaceIds}..remove(placeId),
        );

  factory CopilotProfile.fromJson(Map<String, dynamic> j) => CopilotProfile(
        interests: {
          for (final entry in (j['interests'] as Map<String, dynamic>? ?? {}).entries)
            if (CopilotTopic.values.where((t) => t.name == entry.key).isNotEmpty)
              CopilotTopic.values.firstWhere((t) => t.name == entry.key):
                  InterestLevel.values.firstWhere(
                (l) => l.name == entry.value,
                orElse: () => InterestLevel.medium,
              ),
        },
        sarcasm: InterestLevel.values.firstWhere(
          (l) => l.name == j['sarcasm'],
          orElse: () => InterestLevel.high,
        ),
        talkAmount: InterestLevel.values.firstWhere(
          (l) => l.name == j['talk_amount'],
          orElse: () => InterestLevel.medium,
        ),
        visitedPlaceIds: {...(j['visited'] as List? ?? const [])}.cast<String>(),
        discussedPlaceIds: {...(j['discussed'] as List? ?? const [])}.cast<String>(),
        likedPlaceIds: {...(j['liked'] as List? ?? const [])}.cast<String>(),
        dislikedPlaceIds: {...(j['disliked'] as List? ?? const [])}.cast<String>(),
      );

  Map<String, dynamic> toJson() => {
        'interests': {for (final e in interests.entries) e.key.name: e.value.name},
        'sarcasm': sarcasm.name,
        'talk_amount': talkAmount.name,
        'visited': visitedPlaceIds.toList(),
        'discussed': discussedPlaceIds.toList(),
        'liked': likedPlaceIds.toList(),
        'disliked': dislikedPlaceIds.toList(),
      };
}
