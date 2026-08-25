/// One player's progress through THE GUIDE's introduction (`explorer_profiles`,
/// migration 0074) — self-only RLS, one row per user. Mirrors
/// `MissionProgress`'s shape/style, but this tracks whole-game onboarding
/// state, not progress through any one mission.
class ExplorerProfile {
  const ExplorerProfile({
    required this.id,
    required this.userId,
    this.guideStatus = kGuideStatusNotStarted,
    this.activatedAt,
  });

  final String id;
  final String userId;

  /// not_started | introduction_started | introduction_completed | explorer_activated
  final String guideStatus;
  final DateTime? activatedAt;

  bool get hasCompletedIntroduction =>
      guideStatus == kGuideStatusIntroductionCompleted || guideStatus == kGuideStatusExplorerActivated;
  bool get isExplorerActivated => guideStatus == kGuideStatusExplorerActivated;

  /// True until the player has finished (or at least started) meeting the
  /// Guide — this is what decides whether `GuideIntroScreen` auto-launches.
  bool get needsIntroduction =>
      guideStatus == kGuideStatusNotStarted || guideStatus == kGuideStatusIntroductionStarted;

  factory ExplorerProfile.fromJson(Map<String, dynamic> j) => ExplorerProfile(
        id: (j['id'] ?? '').toString(),
        userId: (j['user_id'] ?? '').toString(),
        guideStatus: (j['guide_status'] ?? kGuideStatusNotStarted) as String,
        activatedAt: DateTime.tryParse('${j['activated_at']}'),
      );

  Map<String, dynamic> toWrite() => {
        'user_id': userId,
        'guide_status': guideStatus,
        'activated_at': activatedAt?.toIso8601String(),
      };

  ExplorerProfile copyWith({String? guideStatus, DateTime? activatedAt}) => ExplorerProfile(
        id: id,
        userId: userId,
        guideStatus: guideStatus ?? this.guideStatus,
        activatedAt: activatedAt ?? this.activatedAt,
      );
}

const kGuideStatusNotStarted = 'not_started';
const kGuideStatusIntroductionStarted = 'introduction_started';
const kGuideStatusIntroductionCompleted = 'introduction_completed';
const kGuideStatusExplorerActivated = 'explorer_activated';
