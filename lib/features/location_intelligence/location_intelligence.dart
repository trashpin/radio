import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/location_intelligence/models/content_item.dart';

/// Meters per mile.
const double _mile = 1609.344;

/// Distance → priority score. Nearby wins big; beyond 20 miles is 0 (never
/// auto-played), so the visitor never hears about a place 100 miles away.
int priorityForDistance(double meters) {
  final mi = meters / _mile;
  if (mi <= 1) return 100;
  if (mi <= 3) return 90;
  if (mi <= 5) return 80;
  if (mi <= 10) return 60;
  if (mi <= 20) return 40;
  return 0;
}

/// A content item paired with its live distance + priority.
class RankedContent {
  const RankedContent(this.item, this.distanceMeters, this.priority);
  final ContentItem item;
  final double distanceMeters;
  final int priority;

  /// Distance priority plus the author's base bump — used for ordering.
  int get score => priority + item.basePriority;
}

/// A resolved snapshot of where the visitor is and what's around them.
class LocationContext {
  const LocationContext({
    required this.latitude,
    required this.longitude,
    required this.nearby,
    this.headingDegrees,
    this.speedMps = 0,
    this.county,
    this.city,
    this.state,
    this.park,
    this.timestamp,
  });

  final double latitude;
  final double longitude;
  final double? headingDegrees;
  final double speedMps;

  /// Derived from the nearest geocoded content (no reverse-geocoding API).
  final String? county;
  final String? city;
  final String? state;
  final String? park;

  /// Everything within 20 miles, best-first (priority desc, then distance).
  final List<RankedContent> nearby;
  final DateTime? timestamp;

  RankedContent? nearestOf(ContentCategory category) {
    for (final r in nearby) {
      if (r.item.category == category) return r;
    }
    return null;
  }

  static const empty = LocationContext(latitude: 0, longitude: 0, nearby: []);
  bool get hasFix => latitude != 0 || longitude != 0;
}

/// Area transitions the radio reacts to with a welcome/departure.
enum LocationTransition { enteredCounty, enteredCity, enteredPark, leftPark }

/// What the radio should air next.
enum RadioSlotKind { narration, music, dj, interestingFact, stationId, silent }

class RadioDecision {
  const RadioDecision(this.kind, {this.item, this.reason = '', this.transition});
  final RadioSlotKind kind;
  final ContentItem? item;
  final String reason;
  final LocationTransition? transition;

  @override
  String toString() => item != null
      ? '${kind.name}: ${item!.title} · $reason'
      : '${kind.name} · $reason';
}

/// Mutable per-trip memory: what's been heard, the music streak, where we are,
/// and how far through the opening programming sequence we are.
class TripState {
  final Set<String> played = {};
  final Map<String, DateTime> lastPlayedAt = {};
  int songsInARow = 0;
  int phaseIndex = 0;
  String? currentCounty;
  String? currentCity;
  String? currentPark;

  void markPlayedContent(ContentItem item, {DateTime? now}) {
    played.add(item.id);
    lastPlayedAt[item.id] = now ?? DateTime.now();
    songsInARow = 0;
  }

  void markMusic() => songsInARow++;
  void markTalk() => songsInARow = 0;
}

/// The opening programming clock (from the brief). Music steps are interleaved;
/// category steps are filled by the highest-priority nearby content of that
/// category. Empty steps are skipped.
const List<ContentCategory> kProgramOrder = [
  ContentCategory.welcome,
  ContentCategory.countyWelcome,
  ContentCategory.music,
  ContentCategory.countyHistory,
  ContentCategory.music,
  ContentCategory.cityWelcome,
  ContentCategory.music,
  ContentCategory.communityStory,
  ContentCategory.music,
  ContentCategory.riverStory,
  ContentCategory.music,
  ContentCategory.historicLandmark,
  ContentCategory.music,
  ContentCategory.scenicDrive,
  ContentCategory.music,
  ContentCategory.arrival, // park welcome (only when a park is near)
  ContentCategory.parkStory,
  ContentCategory.wildlife,
  ContentCategory.plants,
  ContentCategory.hiddenGem,
];

/// Categories rotated through in steady state — the whole story of the area,
/// with parks as just one layer among many.
const List<ContentCategory> kDiscoveryRotation = [
  ContentCategory.countyFunFacts,
  ContentCategory.cityHistory,
  ContentCategory.riverStory,
  ContentCategory.countyNature,
  ContentCategory.wildlife,
  ContentCategory.communityStory,
  ContentCategory.countyAgriculture,
  ContentCategory.lakeStory,
  ContentCategory.history,
  ContentCategory.plants,
  ContentCategory.cityFunFacts,
  ContentCategory.forestStory,
  ContentCategory.countyEconomy,
  ContentCategory.birds,
  ContentCategory.scenicOverlook,
  ContentCategory.trees,
  ContentCategory.trails,
  ContentCategory.hiddenGem,
  ContentCategory.countyHiddenGems,
  ContentCategory.attraction,
  ContentCategory.museum,
  ContentCategory.water,
];

/// The Location Intelligence Engine — a pure brain that turns GPS + geocoded
/// content into a location-aware radio programme. No I/O; fully testable.
class LocationIntelligenceEngine {
  const LocationIntelligenceEngine({this.maxSongsInARow = 3});

  /// Hard cap on consecutive songs (brief: never more than three).
  final int maxSongsInARow;

  /// Builds the live context: distance/priority for everything within 20 miles,
  /// best-first, plus county/city/state/park derived from the nearest content
  /// that carries each field.
  LocationContext deriveContext(
    double latitude,
    double longitude,
    List<ContentItem> all, {
    double? headingDegrees,
    double speedMps = 0,
    DateTime? now,
  }) {
    final ranked = <RankedContent>[];
    // For geocoding: track the nearest item carrying each field.
    ContentItem? nCounty, nCity, nState, nPark;
    double dCounty = double.infinity,
        dCity = double.infinity,
        dState = double.infinity,
        dPark = double.infinity;

    for (final item in all) {
      if (!item.hasCoordinates) continue;
      final dist = GeoMath.distanceMeters(
          latitude, longitude, item.latitude, item.longitude);
      final pri = priorityForDistance(dist);
      final withinRadius =
          item.radiusMeters != null && dist <= item.radiusMeters!;
      if (pri > 0 || withinRadius) {
        ranked.add(RankedContent(item, dist, pri == 0 ? 40 : pri));
      }
      if (item.county != null && dist < dCounty) {
        dCounty = dist;
        nCounty = item;
      }
      if (item.city != null && dist < dCity) {
        dCity = dist;
        nCity = item;
      }
      if (item.state != null && dist < dState) {
        dState = dist;
        nState = item;
      }
      if (item.park != null && dist < dPark) {
        dPark = dist;
        nPark = item;
      }
    }

    ranked.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0
          ? byScore
          : a.distanceMeters.compareTo(b.distanceMeters);
    });

    // "Current park" only counts when we're actually within its radius (or very
    // close), so we don't claim to be in a park 15 miles away.
    String? park;
    if (nPark != null && dPark <= (nPark.radiusMeters ?? (5 * _mile))) {
      park = nPark.park;
    }

    return LocationContext(
      latitude: latitude,
      longitude: longitude,
      headingDegrees: headingDegrees,
      speedMps: speedMps,
      county: nCounty?.county,
      city: dCity <= 10 * _mile ? nCity?.city : null,
      state: nState?.state,
      park: park,
      nearby: ranked,
      timestamp: now,
    );
  }

  /// Eligible nearby content (within range, not heard this trip, cooldown ok),
  /// best-first.
  List<RankedContent> rankNearby(
    LocationContext ctx,
    TripState trip, {
    DateTime? now,
    ContentCategory? category,
  }) {
    final t = now ?? DateTime.now();
    return ctx.nearby
        .where((r) =>
            (category == null || r.item.category == category) &&
            _eligible(r, trip, t))
        .toList();
  }

  bool _eligible(RankedContent r, TripState trip, DateTime now) {
    if (trip.played.contains(r.item.id)) return false;
    final last = trip.lastPlayedAt[r.item.id] ?? r.item.lastPlayed;
    if (last != null && now.difference(last) < r.item.cooldown) return false;
    if (r.item.radiusMeters != null && r.distanceMeters > r.item.radiusMeters!) {
      return false;
    }
    return true;
  }

  /// Which fresh area transitions apply right now (compared to trip memory).
  List<LocationTransition> pendingTransitions(
      LocationContext ctx, TripState trip) {
    final out = <LocationTransition>[];
    if (ctx.county != null && ctx.county != trip.currentCounty) {
      out.add(LocationTransition.enteredCounty);
    }
    if (ctx.city != null && ctx.city != trip.currentCity) {
      out.add(LocationTransition.enteredCity);
    }
    if (ctx.park != null && ctx.park != trip.currentPark) {
      out.add(LocationTransition.enteredPark);
    }
    if (ctx.park == null && trip.currentPark != null) {
      out.add(LocationTransition.leftPark);
    }
    return out;
  }

  /// The core decision: what to air next. Mutates [trip] (records the play, the
  /// music streak, and area memory). Handles area transitions first, then the
  /// opening programming order, then steady-state discovery — always honoring
  /// the max-songs-in-a-row rule and never repeating within the trip.
  RadioDecision next(LocationContext ctx, TripState trip, {DateTime? now}) {
    final t = now ?? DateTime.now();

    // 1) Area transitions → welcome / town intro / park welcome / departure.
    final transition = _handleTransition(ctx, trip, t);
    if (transition != null) return transition;

    // 2) Opening programming sequence.
    if (trip.phaseIndex < kProgramOrder.length) {
      final seq = _openingStep(ctx, trip, t);
      if (seq != null) return seq;
    }

    // 3) Steady state: music-forward, but broken up by nearby talk and capped
    // at maxSongsInARow.
    if (trip.songsInARow >= maxSongsInARow) {
      return _talk(ctx, trip, t, reason: 'music cap');
    }
    // Music-forward cadence: allow up to (cap-1) songs, then a talk break.
    if (trip.songsInARow >= (maxSongsInARow - 1)) {
      final talk = _talk(ctx, trip, t, reason: 'break');
      if (talk.kind != RadioSlotKind.silent) return talk;
    }
    return _music(trip, reason: 'steady');
  }

  RadioDecision? _handleTransition(
      LocationContext ctx, TripState trip, DateTime now) {
    for (final tr in pendingTransitions(ctx, trip)) {
      switch (tr) {
        case LocationTransition.enteredCounty:
          trip.currentCounty = ctx.county;
          final r = _firstEligible(ctx, trip, now, [
            ContentCategory.countyWelcome,
            ContentCategory.countyHistory,
            ContentCategory.welcome,
          ]);
          if (r != null) {
            trip.markPlayedContent(r.item, now: now);
            return RadioDecision(RadioSlotKind.narration,
                item: r.item, reason: 'county welcome', transition: tr);
          }
        case LocationTransition.enteredCity:
          trip.currentCity = ctx.city;
          final r = _firstEligible(ctx, trip, now, [
            ContentCategory.cityWelcome,
            ContentCategory.cityIntro,
            ContentCategory.communityStory,
          ]);
          if (r != null) {
            trip.markPlayedContent(r.item, now: now);
            return RadioDecision(RadioSlotKind.narration,
                item: r.item, reason: 'town intro', transition: tr);
          }
        case LocationTransition.enteredPark:
          trip.currentPark = ctx.park;
          final r = _firstEligible(ctx, trip, now,
              [ContentCategory.arrival, ContentCategory.park]);
          if (r != null) {
            trip.markPlayedContent(r.item, now: now);
            return RadioDecision(RadioSlotKind.narration,
                item: r.item, reason: 'park welcome', transition: tr);
          }
        case LocationTransition.leftPark:
          final left = trip.currentPark;
          trip.currentPark = null;
          final r = ctx.nearby.firstWhereOrNull((x) =>
              x.item.category == ContentCategory.departure &&
              x.item.park == left &&
              _eligible(x, trip, now));
          if (r != null) {
            trip.markPlayedContent(r.item, now: now);
            return RadioDecision(RadioSlotKind.narration,
                item: r.item, reason: 'departure', transition: tr);
          }
      }
    }
    return null;
  }

  /// Walks the opening clock, skipping empty steps, until it finds something to
  /// air (or the sequence completes).
  RadioDecision? _openingStep(LocationContext ctx, TripState trip, DateTime now) {
    var guard = 0;
    while (trip.phaseIndex < kProgramOrder.length && guard++ < kProgramOrder.length) {
      final step = kProgramOrder[trip.phaseIndex];
      if (step.isMusic) {
        if (trip.songsInARow >= maxSongsInARow) {
          // Can't add a 4th song here — insert a talk break without consuming
          // the music step (it airs next time).
          final talk = _talk(ctx, trip, now, reason: 'music cap');
          if (talk.kind != RadioSlotKind.silent) return talk;
        }
        trip.phaseIndex++;
        return _music(trip, reason: 'programme');
      }
      final r = _firstEligible(ctx, trip, now, [step]);
      trip.phaseIndex++;
      if (r != null) {
        trip.markPlayedContent(r.item, now: now);
        return RadioDecision(RadioSlotKind.narration,
            item: r.item, reason: 'programme: ${step.id}');
      }
      // else: empty step, loop to the next one.
    }
    return null;
  }

  /// Prefers a nearby narration (rotating categories), else DJ banter, else an
  /// interesting fact; silent only if truly nothing.
  RadioDecision _talk(LocationContext ctx, TripState trip, DateTime now,
      {String reason = 'talk'}) {
    // Rotate discovery categories so talk breaks feel varied.
    for (final cat in kDiscoveryRotation) {
      final r = _firstEligible(ctx, trip, now, [cat]);
      if (r != null) {
        trip.markPlayedContent(r.item, now: now);
        return RadioDecision(RadioSlotKind.narration,
            item: r.item, reason: '$reason: ${cat.id}');
      }
    }
    // Any remaining eligible nearby content.
    final any = rankNearby(ctx, trip, now: now);
    if (any.isNotEmpty) {
      trip.markPlayedContent(any.first.item, now: now);
      return RadioDecision(RadioSlotKind.narration,
          item: any.first.item, reason: '$reason: nearby');
    }
    trip.markTalk();
    return RadioDecision(RadioSlotKind.dj, reason: reason);
  }

  RadioDecision _music(TripState trip, {String reason = 'music'}) {
    trip.markMusic();
    return RadioDecision(RadioSlotKind.music, reason: reason);
  }

  RankedContent? _firstEligible(LocationContext ctx, TripState trip,
      DateTime now, List<ContentCategory> categories) {
    for (final cat in categories) {
      final r = ctx.nearby.firstWhereOrNull(
          (x) => x.item.category == cat && _eligible(x, trip, now));
      if (r != null) return r;
    }
    return null;
  }
}

extension _FirstWhereOrNull<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
