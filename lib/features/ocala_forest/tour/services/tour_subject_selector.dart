import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_location.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_trail.dart';
import 'package:explorer_os_mobile/features/ocala_forest/tour/models/tour_story_type.dart';
import 'package:explorer_os_mobile/features/ocala_forest/tour/models/tour_subject.dart';
import 'package:explorer_os_mobile/features/ocala_forest/tour/models/tour_type.dart';

/// Pure "what should the guide talk about next" logic — no Riverpod, no
/// I/O, no GPS/geofence code of its own (that lives in [ForestTourEngine],
/// which wraps the SAME `LocationTriggerEngine`/`nearestTrailId` every
/// other forest feature already uses). Two entry points, deliberately
/// different in one way:
///
/// - [selectForMovement] can return null — used by the passive,
///   movement-driven tour so it stays quiet between meaningful arrivals
///   (spec §9: "do not talk constantly").
/// - [selectOnDemand] never returns null — used by explicit user actions
///   ("Take Me On A Tour", "Tell Me Something"), which must always produce
///   something, falling all the way back to [TourSubject.general] rather
///   than an error (spec §8 TEST 8).
class TourSubjectSelector {
  const TourSubjectSelector();

  TourSubject? selectForMovement({
    required double lat,
    required double lng,
    required List<ForestLocation> locations,
    required List<ForestTrail> trails,
    String? preferredTrailId,
    Set<String> arrivedLocationIds = const {},
    required Set<String> recentlyDiscussedIds,
    TourType tourType = TourType.general,
  }) {
    if (preferredTrailId != null && !recentlyDiscussedIds.contains(preferredTrailId)) {
      final trail = _findTrail(trails, preferredTrailId);
      if (trail != null) return TourSubject.forTrail(trail);
    }
    if (arrivedLocationIds.isNotEmpty) {
      final eligible = _eligible(locations, tourType)
          .where((l) => arrivedLocationIds.contains(l.id) && !recentlyDiscussedIds.contains(l.id))
          .toList();
      if (eligible.isNotEmpty) {
        return TourSubject.forLocation(_nearest(eligible, lat, lng));
      }
    }
    return null;
  }

  TourSubject selectOnDemand({
    required double lat,
    required double lng,
    required List<ForestLocation> locations,
    required List<ForestTrail> trails,
    String? preferredTrailId,
    required Set<String> recentlyDiscussedIds,
    TourType tourType = TourType.general,
  }) {
    if (preferredTrailId != null && !recentlyDiscussedIds.contains(preferredTrailId)) {
      final trail = _findTrail(trails, preferredTrailId);
      if (trail != null) return TourSubject.forTrail(trail);
    }

    final matching = _eligible(locations, tourType).toList();

    final undiscussed = matching.where((l) => !recentlyDiscussedIds.contains(l.id)).toList();
    if (undiscussed.isNotEmpty) return TourSubject.forLocation(_nearest(undiscussed, lat, lng));

    // Everything nearby has already been discussed this tour — repeat the
    // nearest rather than go silent or error (spec §8 TEST 8's spirit
    // extends here: always produce something).
    if (matching.isNotEmpty) return TourSubject.forLocation(_nearest(matching, lat, lng));

    return TourSubject.general;
  }

  Iterable<ForestLocation> _eligible(List<ForestLocation> locations, TourType tourType) sync* {
    for (final l in locations) {
      if (!l.active) continue;
      if (!tourType.matches(l.category, TourStoryType.fromStoryCategory(l.storyCategory))) continue;
      yield l;
    }
  }

  ForestLocation _nearest(List<ForestLocation> candidates, double lat, double lng) {
    candidates.sort((a, b) => GeoMath.distanceMeters(lat, lng, a.latitude, a.longitude)
        .compareTo(GeoMath.distanceMeters(lat, lng, b.latitude, b.longitude)));
    return candidates.first;
  }

  ForestTrail? _findTrail(List<ForestTrail> trails, String id) {
    for (final t in trails) {
      if (t.id == id) return t;
    }
    return null;
  }
}
