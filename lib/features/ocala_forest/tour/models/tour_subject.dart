import 'package:explorer_os_mobile/features/ocala_forest/models/forest_location.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_trail.dart';
import 'package:explorer_os_mobile/features/ocala_forest/tour/models/tour_story_type.dart';

enum TourSubjectKind { location, trail, general }

/// One thing the tour guide is about to talk about — a real
/// [ForestLocation], a real [ForestTrail], or [general] (the forest as a
/// whole, used when nothing specific is nearby/undiscussed, spec §8 TEST
/// 8 — never an error state). This is the one shape both the passive
/// movement engine and the on-demand "Tell Me Something"/tour-start paths
/// produce, so the narration-request code only has to handle one type.
class TourSubject {
  const TourSubject._({
    required this.kind,
    required this.id,
    required this.name,
    this.location,
    this.trail,
    this.storyType = TourStoryType.general,
    this.isExactMatch = true,
  });

  factory TourSubject.forLocation(ForestLocation location, {bool isExactMatch = true}) =>
      TourSubject._(
        kind: TourSubjectKind.location,
        id: location.id,
        name: location.name,
        location: location,
        storyType: TourStoryType.fromStoryCategory(location.storyCategory),
        isExactMatch: isExactMatch,
      );

  factory TourSubject.forTrail(ForestTrail trail, {bool isExactMatch = true}) => TourSubject._(
        kind: TourSubjectKind.trail,
        id: trail.id,
        name: (trail.trailName?.trim().isNotEmpty ?? false)
            ? trail.trailName!.trim()
            : 'Trail ${trail.trailNo}',
        trail: trail,
        // A trail's own official attributes are verified USFS data, never
        // folklore — always classified as nature/verified content.
        storyType: TourStoryType.nature,
        isExactMatch: isExactMatch,
      );

  static const TourSubject general = TourSubject._(
    kind: TourSubjectKind.general,
    id: 'general',
    name: 'Ocala National Forest',
    storyType: TourStoryType.general,
    isExactMatch: false,
  );

  final TourSubjectKind kind;
  final String id;
  final String name;
  final ForestLocation? location;
  final ForestTrail? trail;
  final TourStoryType storyType;

  /// True when the visitor's real GPS position is confidently WITHIN this
  /// subject's own geofence/trail line (spec §18: never imply the visitor
  /// is standing on the exact site unless the geofence actually confirms
  /// that). False for a merely-nearby match — the narration must then say
  /// "in this part of the forest" / "near this area," never "right here."
  final bool isExactMatch;
}
