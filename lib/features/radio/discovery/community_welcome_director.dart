import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';

/// A community/town the traveler can approach and enter (from the master
/// `locations` table, type `community` or `city`).
class CommunityPlace {
  const CommunityPlace({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    double? entryRadiusMeters,
    double? approachRadiusMeters,
  }) : entryRadiusMeters = entryRadiusMeters ?? kDefaultEntryMeters,
       approachRadiusMeters = approachRadiusMeters ?? kDefaultApproachMeters;

  final String id;
  final String name;
  final double latitude;
  final double longitude;

  /// Distance under which the traveler is considered INSIDE the community.
  final double entryRadiusMeters;

  /// Distance under which we announce "in about a mile you'll be entering …".
  final double approachRadiusMeters;

  /// ~0.5 mile — being this close counts as arriving in town.
  static const double kDefaultEntryMeters = 800;

  /// ~1 mile — the approach heads-up distance from the spec.
  static const double kDefaultApproachMeters = 1609.344;
}

enum CommunityCueKind { approach, entry }

/// A decision to play something for a community on this GPS update.
class CommunityCue {
  const CommunityCue(this.kind, this.place, this.distanceMeters);
  final CommunityCueKind kind;
  final CommunityPlace place;
  final double distanceMeters;
}

/// Per-community, per-visit memory.
class _Visit {
  bool approached = false;
  bool entered = false;
}

/// Decides, purely from GPS position, when to announce that the traveler is
/// APPROACHING a community (~1 mile out) and when they've ENTERED it — each at
/// most once per visit. A community becomes eligible again once the traveler
/// travels well clear of it (a new visit), so a there-and-back drive re-plays.
///
/// This is deliberately free of Riverpod/audio so it can be unit-tested against
/// a simulated drive; the session wiring turns [CommunityCue]s into radio
/// interruptions.
class CommunityWelcomeDirector {
  CommunityWelcomeDirector({double? leaveMeters})
    : leaveMeters = leaveMeters ?? 3218.69; // ~2 miles clear = visit over

  /// Once the traveler is farther than this from a community, its visit resets.
  final double leaveMeters;

  final Map<String, _Visit> _visits = {};

  /// Evaluate the current position against [places] and return the single most
  /// relevant cue (nearest ENTRY wins over APPROACH), or null if there's
  /// nothing new to say. Marks visit state so cues never repeat within a visit.
  CommunityCue? evaluate(double lat, double lng, List<CommunityPlace> places) {
    CommunityCue? bestEntry;
    CommunityCue? bestApproach;

    for (final p in places) {
      final d = GeoMath.distanceMeters(lat, lng, p.latitude, p.longitude);
      final v = _visits.putIfAbsent(p.id, () => _Visit());

      // Reset the visit once the traveler is clearly past/away from the town.
      if (d > p.approachRadiusMeters + leaveMeters) {
        v.approached = false;
        v.entered = false;
        continue;
      }

      if (d <= p.entryRadiusMeters) {
        if (!v.entered) {
          if (bestEntry == null || d < bestEntry.distanceMeters) {
            bestEntry = CommunityCue(CommunityCueKind.entry, p, d);
          }
        }
      } else if (d <= p.approachRadiusMeters) {
        if (!v.approached) {
          if (bestApproach == null || d < bestApproach.distanceMeters) {
            bestApproach = CommunityCue(CommunityCueKind.approach, p, d);
          }
        }
      }
    }

    final cue = bestEntry ?? bestApproach;
    if (cue == null) return null;
    final v = _visits[cue.place.id]!;
    if (cue.kind == CommunityCueKind.entry) {
      v.entered = true;
      v.approached = true; // don't approach-announce after arriving
    } else {
      v.approached = true;
    }
    return cue;
  }

  /// The default spoken heads-up used when a community has no custom approach
  /// clip ("In about a mile, you'll be entering Belleview.").
  static String approachScript(String name) =>
      "In about a mile, you'll be entering $name.";

  /// A safe spoken fallback for the entry welcome when a community has no
  /// recorded narration or description yet.
  static String entryFallbackScript(String name) => 'Welcome to $name.';

  /// Clears all visit memory (e.g. a brand-new trip).
  void reset() => _visits.clear();
}
