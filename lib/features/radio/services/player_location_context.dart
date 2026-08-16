import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/admin/counties/county_config.dart';
import 'package:explorer_os_mobile/features/admin/counties/county_config_repository.dart';
import 'package:explorer_os_mobile/features/events/data/event_repository.dart';
import 'package:explorer_os_mobile/features/events/models/local_event.dart';
import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/locations/data/location_narration.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/location_engine.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart'
    show formatDistance;
import 'package:explorer_os_mobile/features/radio/models/geo_point.dart';
import 'package:explorer_os_mobile/features/radio/models/tell_me_more_context.dart';

/// The location-aware player's five content tiers, in priority order.
enum PlayerLocationKind { event, park, spring, town, county }

/// "Inside a town" radius when a location has no explicit trigger_radius —
/// same default the existing community-welcome director uses
/// ([CommunityWelcomeDirector.kDefaultEntryMeters]), reused here rather than
/// inventing a second constant.
const double _kTownEntryMeters = 800;

const Set<LocationType> _parkTypes = {
  LocationType.statePark,
  LocationType.nationalPark,
  LocationType.countyPark,
};
const Set<LocationType> _townTypes = {LocationType.city, LocationType.community};

/// What the location-aware player should show right now instead of (or
/// alongside) the normal music artwork — resolved with EVENT > PARK > SPRING
/// > TOWN > COUNTY priority. This is a read-only display/context layer: it
/// never touches playback. Only pressing TELL ME MORE (using
/// [tellMeMoreContext], the single source of truth shared by the card and the
/// button) starts audio.
class PlayerLocationContext {
  const PlayerLocationContext({
    required this.kind,
    required this.title,
    required this.tellMeMoreContext,
    this.imageUrl,
    this.distanceLabel,
    this.teaser,
    this.hours,
  });

  final PlayerLocationKind kind;
  final String title;
  final String? imageUrl;
  final String? distanceLabel;

  /// Short "did you know" hook — never the full story.
  final String? teaser;
  final String? hours;
  final TellMeMoreContext tellMeMoreContext;
}

/// Resolves the active tier from data every piece of which already exists
/// elsewhere in the app: [nearbyEventsProvider] (events), [nearbyLocationsProvider]
/// (park/spring/town — the same ranked list "Nearby Stories" reads), and
/// [gpsControllerProvider.currentCounty] + [countyConfigsProvider] (county).
/// Null when nothing qualifies at all (no GPS fix yet, or truly nowhere
/// recognized) — the player then falls back to its normal music artwork.
final playerLocationContextProvider = Provider<PlayerLocationContext?>((ref) {
  // 1) EVENT — highest priority.
  final events = ref.watch(nearbyEventsProvider);
  if (events.isNotEmpty) {
    return _fromEvent(events.first);
  }

  // 2/3/4) PARK, SPRING, TOWN — same ranked nearby list "Nearby Stories" and
  // the GPS arrival triggers already read; just narrowed by type here.
  //
  // nearbyLocationsProvider's own radius (20 miles) is generous on purpose
  // for that browse list, but it's too generous for "what's near me right
  // now" — a state park 15 miles away must not outrank the town the
  // listener is actually standing in. PARK/SPRING get their own tighter cap
  // so they only preempt TOWN when genuinely close.
  final nearby = ref.watch(nearbyLocationsProvider);
  const parkSpringMaxMeters = 5 * 1609.344;

  final park = _firstOfType(
    nearby,
    _parkTypes,
    within: (n) => n.distanceMeters <= parkSpringMaxMeters,
  );
  if (park != null) {
    return _fromLocation(PlayerLocationKind.park, park);
  }

  final spring = _firstOfType(
    nearby,
    {LocationType.spring},
    within: (n) => n.distanceMeters <= parkSpringMaxMeters,
  );
  if (spring != null) {
    return _fromLocation(PlayerLocationKind.spring, spring);
  }

  final town = _firstOfType(
    nearby,
    _townTypes,
    // "Inside" the town, not merely nearest — same semantics as the existing
    // community-entry welcome (CommunityWelcomeDirector).
    within: (n) => n.distanceMeters <= (n.location.triggerRadius ?? _kTownEntryMeters),
  );
  if (town != null) {
    return _fromLocation(PlayerLocationKind.town, town);
  }

  // 5) COUNTY — lowest priority, always available once GPS knows the county.
  final county = ref.watch(gpsControllerProvider).currentCounty;
  if (county == null || county.trim().isEmpty) return null;
  final configs = ref.watch(countyConfigsProvider).value ?? const [];
  CountyConfig? config;
  for (final c in configs) {
    if (c.key == county.toLowerCase().trim()) {
      config = c;
      break;
    }
  }
  return _fromCounty(county, config);
});

NearbyLocation? _firstOfType(
  List<NearbyLocation> nearby,
  Set<LocationType> types, {
  bool Function(NearbyLocation)? within,
}) {
  for (final n in nearby) {
    if (!types.contains(n.location.type)) continue;
    if (within != null && !within(n)) continue;
    return n;
  }
  return null;
}

String? _teaserFor(MasterLocation loc) {
  if ((loc.shortDescription ?? '').trim().isNotEmpty) {
    return loc.shortDescription!.trim();
  }
  final desc = loc.bestDescription;
  if (desc != null) return desc;
  return composeLocationScript(loc);
}

PlayerLocationContext _fromLocation(PlayerLocationKind kind, NearbyLocation n) {
  final loc = n.location;
  final distanceLabel = formatDistance(n.distanceMeters);
  return PlayerLocationContext(
    kind: kind,
    title: loc.name,
    imageUrl: loc.images.isNotEmpty ? loc.images.first : null,
    distanceLabel: distanceLabel,
    teaser: _teaserFor(loc),
    hours: (loc.hours ?? '').trim().isNotEmpty ? loc.hours : null,
    tellMeMoreContext: TellMeMoreContext(
      subject: loc.name,
      locationId: loc.id,
      contextKind: kind.name,
      banterText: _teaserFor(loc),
      distanceLabel: distanceLabel,
      location: loc.hasCoordinates
          ? GeoPoint(latitude: loc.latitude!, longitude: loc.longitude!)
          : null,
    ),
  );
}

String _formatEventTime(LocalEvent e) {
  String fmt(String hhmmss) {
    final parts = hhmmss.split(':');
    if (parts.length < 2) return hhmmss;
    var h = int.tryParse(parts[0]) ?? 0;
    final m = parts[1];
    final suffix = h >= 12 ? 'PM' : 'AM';
    h = h % 12 == 0 ? 12 : h % 12;
    return '$h:$m $suffix';
  }

  final start = (e.startTime ?? '').isNotEmpty ? fmt(e.startTime!) : null;
  final end = (e.endTime ?? '').isNotEmpty ? fmt(e.endTime!) : null;
  if (start != null && end != null) return '$start – $end';
  return start ?? end ?? '';
}

PlayerLocationContext _fromEvent(NearbyEvent n) {
  final e = n.event;
  final dateLabel = e.eventDate == null
      ? null
      : '${e.eventDate!.month}/${e.eventDate!.day}';
  final timeLabel = _formatEventTime(e);
  final teaserParts = <String>[
    ?e.bestDescription,
    ?dateLabel,
    if (timeLabel.isNotEmpty) timeLabel,
  ];
  final distanceLabel = formatDistance(n.distanceMeters);
  return PlayerLocationContext(
    kind: PlayerLocationKind.event,
    title: e.name,
    imageUrl: e.imageUrl,
    distanceLabel: distanceLabel,
    teaser: teaserParts.isEmpty ? null : teaserParts.join(' · '),
    tellMeMoreContext: TellMeMoreContext(
      subject: e.name,
      locationId: e.id,
      contextKind: PlayerLocationKind.event.name,
      banterText: e.bestDescription,
      distanceLabel: distanceLabel,
      location: e.hasCoordinates
          ? GeoPoint(latitude: e.latitude!, longitude: e.longitude!)
          : null,
    ),
  );
}

PlayerLocationContext _fromCounty(String county, CountyConfig? config) {
  final teaser = config == null
      ? null
      : (config.facts.isNotEmpty
          ? config.facts.first
          : (config.overview ?? config.description));
  return PlayerLocationContext(
    kind: PlayerLocationKind.county,
    title: '$county County',
    imageUrl: config?.heroImageUrl,
    teaser: teaser,
    tellMeMoreContext: TellMeMoreContext(
      subject: county,
      contextKind: PlayerLocationKind.county.name,
      banterText: teaser,
    ),
  );
}
