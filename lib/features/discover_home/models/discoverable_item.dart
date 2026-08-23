import 'package:explorer_os_mobile/features/discover_home/models/interest_tag_mapping.dart';
import 'package:explorer_os_mobile/features/events/data/event_repository.dart';
import 'package:explorer_os_mobile/features/locations/location_engine.dart';
import 'package:explorer_os_mobile/features/nearby_gems/data/nearby_gems_repository.dart';
import 'package:explorer_os_mobile/features/radio/services/player_location_context.dart';

/// The three existing content sources Discover draws from — no new content
/// table, just a normalized view over what `discover_places_provider.dart`
/// already fetches from `nearby_gems`/`events`/`locations`.
enum DiscoverItemKind { gem, event, location }

/// One recommendable thing in Marion County, normalized from whichever real
/// source it came from so cards/scoring/detail don't need to know which.
/// [context] is the exact [PlayerLocationContext] the rest of the app
/// already builds for this record (same image/teaser/TellMeMoreContext the
/// Radio player and old DISCOVER screen use) — reused, not rebuilt.
class DiscoverableItem {
  const DiscoverableItem({
    required this.kind,
    required this.id,
    required this.title,
    required this.interestTags,
    required this.context,
    this.category,
    this.distanceMeters,
    this.eventDate,
    this.featured = false,
    this.priority = 0,
    this.timeOfDay,
  });

  final DiscoverItemKind kind;
  final String id;
  final String title;
  final Set<String> interestTags;
  final PlayerLocationContext context;
  final String? category;
  final double? distanceMeters;

  /// Events only — null for gems/locations.
  final DateTime? eventDate;

  /// Editorial signals (gems only today) used as a fallback ranking signal
  /// when interests don't distinguish two items, or when the visitor hasn't
  /// picked any interests yet.
  final bool featured;
  final int priority;

  /// Events only — see [LocalEvent.timeOfDay]. Derived from the event's own
  /// start time, never guessed from category.
  final String? timeOfDay;

  bool get isEveningOrLater => timeOfDay == 'evening' || timeOfDay == 'late_night';

  String? get imageUrl => context.imageUrl;
  String? get teaser => context.teaser;

  /// `discover-narration`'s `subjectType` — matches [kind] exactly.
  String get narrationSubjectType => switch (kind) {
        DiscoverItemKind.gem => 'gem',
        DiscoverItemKind.event => 'event',
        DiscoverItemKind.location => 'location',
      };
}

DiscoverableItem discoverItemFromGemHit(NearbyGemHit hit) => DiscoverableItem(
      kind: DiscoverItemKind.gem,
      id: hit.gem.id,
      title: hit.gem.name,
      category: hit.gem.category,
      interestTags: interestTagsForGemCategory(hit.gem.category),
      context: playerContextForGem(hit.gem, distanceMeters: hit.distanceMeters),
      distanceMeters: hit.distanceMeters,
      featured: hit.gem.featured,
      priority: hit.gem.priority,
    );

DiscoverableItem discoverItemFromEvent(NearbyEvent n) => DiscoverableItem(
      kind: DiscoverItemKind.event,
      id: n.event.id,
      title: n.event.name,
      category: (n.event.category ?? '').trim().isNotEmpty ? n.event.category : 'Event',
      interestTags: interestTagsForEvent(n.event),
      context: playerContextForEvent(n),
      distanceMeters: n.distanceMeters,
      eventDate: n.event.eventDate,
      timeOfDay: n.event.timeOfDay,
    );

DiscoverableItem discoverItemFromLocation(PlayerLocationKind kind, NearbyLocation n) =>
    DiscoverableItem(
      kind: DiscoverItemKind.location,
      id: n.location.id,
      title: n.location.name,
      category: n.location.type.label,
      interestTags: interestTagsForLocationType(n.location.type),
      context: playerContextForLocation(kind, n),
      distanceMeters: n.distanceMeters,
    );
