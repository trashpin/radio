import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/admin/counties/county_config.dart';
import 'package:explorer_os_mobile/features/admin/counties/county_config_repository.dart';
import 'package:explorer_os_mobile/features/destinations/data/destination_repository.dart';
import 'package:explorer_os_mobile/features/events/data/event_repository.dart';
import 'package:explorer_os_mobile/features/location_intelligence/data/location_content_repository.dart';
import 'package:explorer_os_mobile/features/locations/data/location_narration.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/narration/data/destination_narration_repository.dart';
import 'package:explorer_os_mobile/features/narration/models/destination_narration.dart';
import 'package:explorer_os_mobile/features/radio/models/tell_me_more_context.dart';

/// Maps a DJ Banter category (the `category` token on [TellMeMoreContext])
/// to the ordered list of narration `script_type`s that best answer "tell me
/// more" about that moment. The first type with a published narration wins;
/// later entries are fallbacks so the button still surfaces something useful
/// even when the ideal type hasn't been generated/approved yet.
///
/// Returns an empty list for categories with no narration counterpart
/// (station IDs, song intros/outros, promos) — [TellMeMoreScreen] treats that
/// as "nothing more to add" rather than an empty-content state.
List<String> narrationTypesForBanterCategory(String? categoryId) {
  switch (categoryId) {
    case 'arrival':
      return const ['arrival', 'quick_intro'];
    case 'history_tease':
      return const ['main_history', 'extended_history'];
    case 'wildlife_tease':
      return const ['wildlife', 'birds'];
    case 'bird_tease':
      return const ['birds', 'wildlife'];
    case 'plant_tease':
      return const ['plants', 'trees'];
    case 'geology_tease':
      return const ['geology'];
    case 'interesting_fact':
      return const ['fun_facts'];
    case 'scenic_observation':
      return const ['scenic_highlights'];
    case 'photo_opportunity':
      return const ['photography_tips', 'scenic_highlights'];
    case 'trail_suggestion':
      return const ['nearby_attractions', 'scenic_highlights'];
    case 'hidden_gem':
      return const ['hidden_gems', 'nearby_attractions'];
    case 'family_activity':
      return const ['family_version', 'kids_version'];
    case 'safety_reminder':
      return const ['emergency_info'];
    case 'departure':
      return const ['departure'];
    case 'welcome':
      return const ['quick_intro', 'arrival'];
    default:
      // song_intro, song_outro, station_id, promotion, unknown categories.
      return const [];
  }
}

/// Resolves a `destination_code` (all a DJ Banter Studio clip carries) to the
/// `destination_id` uuid `destination_narrations` is actually keyed by.
/// Cached per code for the app session — codes don't change at runtime.
final _destinationIdByCodeProvider =
    FutureProvider.family<String?, String>((ref, code) async {
  final matches = await ref
      .watch(destinationRepositoryProvider)
      .getWhere('destination_code', code);
  return matches.isEmpty ? null : matches.first.id;
});

/// The best published narration to show for a "Tell Me More" tap, or null
/// when the destination/category has nothing published yet.
final tellMeMoreNarrationProvider = FutureProvider.autoDispose
    .family<DestinationNarration?, TellMeMoreContext>((ref, ctx) async {
  var destinationId = ctx.destinationId;
  if ((destinationId == null || destinationId.isEmpty) &&
      (ctx.destinationCode ?? '').isNotEmpty) {
    // DJ banter clips only carry destination_code today, not destination_id.
    destinationId = await ref.watch(
      _destinationIdByCodeProvider(ctx.destinationCode!).future,
    );
  }
  if (destinationId == null || destinationId.isEmpty) return null;

  final types = narrationTypesForBanterCategory(ctx.category);
  if (types.isEmpty) return null;

  return ref.watch(destinationNarrationRepositoryProvider).bestPublishedFor(
        destinationId: destinationId,
        scriptTypes: types,
      );
});

/// What TELL ME MORE actually shows, unified across every source: a
/// DJ-banter-linked destination narration, a master-location park/spring/
/// town, an event, or a county profile. Every field is optional — only what
/// genuinely exists in the source record is ever populated; nothing here is
/// invented. [TellMeMoreScreen] only ever deals with this one shape.
class TellMeMoreResult {
  const TellMeMoreResult({
    required this.title,
    this.imageUrl,
    this.history,
    this.hours,
    this.admission,
    this.website,
    this.latitude,
    this.longitude,
    this.activities = const [],
    this.goodToKnow = const [],
    this.eventDateLabel,
    this.eventTimeLabel,
    this.locationLabel,
    this.audioUrl,
  });

  final String title;
  final String? imageUrl;

  /// The deep history/background text — never the short player-card teaser.
  final String? history;
  final String? hours;
  final String? admission;

  /// Reservation / official / more-info link, when the source record has one.
  final String? website;
  final double? latitude;
  final double? longitude;

  /// Activities / things to see / county highlights — whatever the source
  /// record already lists; never fabricated.
  final List<String> activities;

  /// Short practical bullets (parking, restrooms, difficulty, accessibility,
  /// population/size/established-year, …) — only the ones present.
  final List<String> goodToKnow;

  /// Event-only.
  final String? eventDateLabel;
  final String? eventTimeLabel;
  final String? locationLabel;

  final String? audioUrl;

  bool get hasAudio => (audioUrl ?? '').trim().isNotEmpty;
  bool get canNavigate => latitude != null && longitude != null;
  bool get hasWebsite => (website ?? '').trim().isNotEmpty;
}

List<String> _goodToKnowFor(MasterLocation loc) => [
      if ((loc.parkingInfo ?? '').trim().isNotEmpty) 'Parking: ${loc.parkingInfo}',
      if ((loc.restrooms ?? '').trim().isNotEmpty) 'Restrooms: ${loc.restrooms}',
      if ((loc.difficulty ?? '').trim().isNotEmpty) 'Difficulty: ${loc.difficulty}',
      if (loc.familyFriendly == true) 'Family friendly',
      if (loc.petFriendly == true) 'Pet friendly',
      if (loc.wheelchairAccessible == true) 'Wheelchair accessible',
    ];

/// The full-story lookup for a park/spring/town: the deepest text this master
/// location has (long description / narration script — deliberately NOT the
/// short teaser), plus every practical field the record already carries, plus
/// whatever audio [resolveLocationNarration] (the same resolver the GPS
/// arrival triggers already use) can find.
final _locationTellMeMoreProvider = FutureProvider.autoDispose
    .family<TellMeMoreResult?, String>((ref, locationId) async {
  final all = await ref.watch(masterLocationsProvider.future);
  MasterLocation? loc;
  for (final l in all) {
    if (l.id == locationId) {
      loc = l;
      break;
    }
  }
  if (loc == null) return null;

  final content = ref.watch(locationContentItemsProvider);
  final resolved = resolveLocationNarration(loc, content);
  final fullText = (loc.longDescription ?? '').trim().isNotEmpty
      ? loc.longDescription!.trim()
      : ((loc.narrationScript ?? '').trim().isNotEmpty
          ? loc.narrationScript!.trim()
          : resolved.text);

  return TellMeMoreResult(
    title: loc.name,
    imageUrl: loc.images.isNotEmpty ? loc.images.first : null,
    history: fullText,
    hours: (loc.hours ?? '').trim().isNotEmpty ? loc.hours : null,
    admission: (loc.admission ?? '').trim().isNotEmpty ? loc.admission : null,
    website: (loc.externalWebsite ?? '').trim().isNotEmpty
        ? loc.externalWebsite
        : null,
    latitude: loc.latitude,
    longitude: loc.longitude,
    activities: loc.tags,
    goodToKnow: _goodToKnowFor(loc),
    audioUrl: resolved.hasAudio ? resolved.audioUrl : null,
  );
});

final _eventTellMeMoreProvider = FutureProvider.autoDispose
    .family<TellMeMoreResult?, String>((ref, eventId) async {
  final all = await ref.watch(eventsProvider.future);
  for (final e in all) {
    if (e.id != eventId) continue;
    final locationLabel = [e.city, e.county]
        .where((s) => (s ?? '').trim().isNotEmpty)
        .join(', ');
    final dateLabel = e.eventDate == null
        ? null
        : '${e.eventDate!.month}/${e.eventDate!.day}/${e.eventDate!.year}';
    final timeParts = [
      if ((e.startTime ?? '').isNotEmpty) e.startTime,
      if ((e.endTime ?? '').isNotEmpty) e.endTime,
    ].whereType<String>();
    return TellMeMoreResult(
      title: e.name,
      imageUrl: e.imageUrl,
      history: e.bestDescription,
      website: (e.externalWebsite ?? '').trim().isNotEmpty
          ? e.externalWebsite
          : null,
      latitude: e.latitude,
      longitude: e.longitude,
      eventDateLabel: dateLabel,
      eventTimeLabel: timeParts.isEmpty ? null : timeParts.join(' – '),
      locationLabel: locationLabel.isEmpty ? null : locationLabel,
    );
  }
  return null;
});

final _countyTellMeMoreProvider = FutureProvider.autoDispose
    .family<TellMeMoreResult?, String>((ref, county) async {
  final configs = await ref.watch(countyConfigsProvider.future);
  CountyConfig? config;
  for (final c in configs) {
    if (c.key == county.toLowerCase().trim()) {
      config = c;
      break;
    }
  }
  if (config == null) return TellMeMoreResult(title: '$county County');

  final text = (config.history ?? '').trim().isNotEmpty
      ? config.history!.trim()
      : config.overview;
  final goodToKnow = [
    if (config.population != null) 'Population: ${config.population}',
    if (config.sizeSqMiles != null) '${config.sizeSqMiles} sq mi',
    if (config.yearEstablished != null) 'Established ${config.yearEstablished}',
  ];
  return TellMeMoreResult(
    title: '$county County',
    imageUrl: config.heroImageUrl,
    history: text,
    website: (config.officialWebsite ?? '').trim().isNotEmpty
        ? config.officialWebsite
        : null,
    activities: [
      ...config.facts,
      if ((config.tourismInfo ?? '').trim().isNotEmpty) config.tourismInfo!,
    ],
    goodToKnow: goodToKnow,
    audioUrl: config.welcomeNarrationUrl,
  );
});

/// The single entry point [TellMeMoreScreen] uses: routes to the right
/// content source based on [TellMeMoreContext.contextKind] (park/spring/town
/// via the master location, event via `events`, county via the county
/// profile), falling back to the original DJ-banter destination-narration
/// lookup when [TellMeMoreContext.contextKind] is null (unchanged behavior).
final tellMeMoreResultProvider = FutureProvider.autoDispose
    .family<TellMeMoreResult?, TellMeMoreContext>((ref, ctx) async {
  switch (ctx.contextKind) {
    case 'park':
    case 'spring':
    case 'town':
      final id = ctx.locationId;
      if (id == null || id.isEmpty) return null;
      return ref.watch(_locationTellMeMoreProvider(id).future);
    case 'event':
      final id = ctx.locationId;
      if (id == null || id.isEmpty) return null;
      return ref.watch(_eventTellMeMoreProvider(id).future);
    case 'county':
      final county = ctx.subject;
      if (county == null || county.isEmpty) return null;
      return ref.watch(_countyTellMeMoreProvider(county).future);
    default:
      final narration = await ref.watch(tellMeMoreNarrationProvider(ctx).future);
      if (narration == null) return null;
      return TellMeMoreResult(
        title: narration.title ?? narration.type?.label ?? 'The full story',
        history: narration.script,
        audioUrl: narration.hasAudio ? narration.audioUrl : null,
      );
  }
});
