/// Every supported location type in ExplorerOS (the master taxonomy). The `id`
/// matches the `category` stored in the `locations` table.
enum LocationType {
  county('county', 'County'),
  city('city', 'City'),
  community('community', 'Community'),
  lake('lake', 'Lake'),
  river('river', 'River'),
  spring('spring', 'Spring'),
  forest('forest', 'Forest'),
  statePark('state_park', 'State Park'),
  nationalPark('national_park', 'National Park'),
  countyPark('county_park', 'County Park'),
  historicSite('historic_site', 'Historic Site'),
  historicDistrict('historic_district', 'Historic District'),
  scenicRoad('scenic_road', 'Scenic Road'),
  trail('trail', 'Trail'),
  trailhead('trailhead', 'Trailhead'),
  campground('campground', 'Campground'),
  boatRamp('boat_ramp', 'Boat Ramp'),
  visitorCenter('visitor_center', 'Visitor Center'),
  wildlifeViewing('wildlife_viewing', 'Wildlife Viewing'),
  scenicOverlook('scenic_overlook', 'Scenic Overlook'),
  museum('museum', 'Museum'),
  attraction('attraction', 'Attraction'),
  restaurant('restaurant', 'Restaurant'),
  gasStation('gas_station', 'Gas Station'),
  parking('parking', 'Parking'),
  safetyAlert('safety_alert', 'Safety Alert'),
  hiddenGem('hidden_gem', 'Hidden Gem'),
  pointOfInterest('point_of_interest', 'Point of Interest'),
  area('area', 'Area / District');

  const LocationType(this.id, this.label);
  final String id;
  final String label;

  static LocationType fromId(String? raw) {
    final n = (raw ?? '').trim().toLowerCase();
    for (final t in LocationType.values) {
      if (t.id == n || t.name.toLowerCase() == n) return t;
    }
    // Loose keyword fallback for free-form sources.
    bool has(String s) => n.contains(s);
    if (has('county')) return LocationType.county;
    if (has('community') || has('unincorporated')) {
      return LocationType.community;
    }
    if (has('city') || has('town')) return LocationType.city;
    if (has('spring')) return LocationType.spring;
    if (has('river') || has('creek')) return LocationType.river;
    if (has('lake') || has('pond')) return LocationType.lake;
    if (has('national forest') || has('forest')) return LocationType.forest;
    if (has('national park')) return LocationType.nationalPark;
    if (has('state park')) return LocationType.statePark;
    if (has('county park')) return LocationType.countyPark;
    if (has('historic district')) return LocationType.historicDistrict;
    if (has('histor') || has('fort') || has('heritage')) {
      return LocationType.historicSite;
    }
    if (has('scenic road') || has('byway') || has('highway')) {
      return LocationType.scenicRoad;
    }
    if (has('trailhead')) return LocationType.trailhead;
    if (has('trail')) return LocationType.trail;
    if (has('camp')) return LocationType.campground;
    if (has('boat') || has('ramp')) return LocationType.boatRamp;
    if (has('visitor')) return LocationType.visitorCenter;
    if (has('wildlife')) return LocationType.wildlifeViewing;
    if (has('overlook') || has('vista') || has('scenic')) {
      return LocationType.scenicOverlook;
    }
    if (has('museum')) return LocationType.museum;
    if (has('restaurant') || has('food') || has('dining')) {
      return LocationType.restaurant;
    }
    if (has('gas') || has('fuel')) return LocationType.gasStation;
    if (has('parking')) return LocationType.parking;
    if (has('safety') || has('alert') || has('warning')) {
      return LocationType.safetyAlert;
    }
    if (has('hidden') || has('gem')) return LocationType.hiddenGem;
    if (has('attraction')) return LocationType.attraction;
    if (has('district') || has('area')) return LocationType.area;
    return LocationType.pointOfInterest;
  }
}

/// Lifecycle/readiness of a location, derived from its content + flags.
///  • ready    — has audio; appears on the map, radio & GPS eligible.
///  • pending  — active but no audio yet ("Needs Narration"); hidden from
///               users by default, visible in admin.
///  • disabled — inactive or hidden; off the map, radio, and search.
enum LocationStatus {
  ready('Ready'),
  pending('Needs Narration'),
  disabled('Disabled');

  const LocationStatus(this.label);
  final String label;
}

/// Explicit editorial workflow status (the `content_status` column, migration
/// 0038) — separate from the computed [LocationStatus] above. Settable by an
/// admin; [MasterLocation.effectiveContentStatus] supplies a sensible default
/// for rows where it hasn't been set yet.
enum ContentStatus {
  draft('draft', 'Draft'),
  needsImages('needs_images', 'Needs Images'),
  needsNarration('needs_narration', 'Needs Narration'),
  needsGpsVerification('needs_gps_verification', 'Needs GPS Verification'),
  needsReview('needs_review', 'Needs Review'),
  published('published', 'Published'),
  archived('archived', 'Archived');

  const ContentStatus(this.id, this.label);
  final String id;
  final String label;

  static ContentStatus? fromId(String? raw) {
    if (raw == null) return null;
    for (final s in ContentStatus.values) {
      if (s.id == raw) return s;
    }
    return null;
  }
}

/// The one canonical location record every system reads (`public.locations`).
class MasterLocation {
  const MasterLocation({
    required this.id,
    required this.name,
    required this.type,
    this.latitude,
    this.longitude,
    this.county,
    this.city,
    this.community,
    this.address,
    this.description,
    this.triggerRadius,
    this.mapVisibilityRadius,
    this.priority = 0,
    this.narrationIds = const [],
    this.audioFiles = const [],
    this.images = const [],
    this.videos = const [],
    this.relatedLocations = const [],
    this.active = true,
    this.featured = false,
    this.hidden = false,
    this.source,
    this.sourceId,
    this.destinationCode,
    this.updatedAt,
    this.createdAt,
    this.state,
    this.shortDescription,
    this.longDescription,
    this.narrationScript,
    this.hours,
    this.admission,
    this.externalWebsite,
    this.parkingInfo,
    this.restrooms,
    this.difficulty,
    this.tags = const [],
    this.familyFriendly,
    this.petFriendly,
    this.wheelchairAccessible,
    this.arrivalTrigger = true,
    this.departureTrigger = false,
    this.playOnce = false,
    this.cooldownSeconds,
    this.contentStatus,
    this.estimatedListeningMinutes,
  });

  final String id;
  final String name;
  final LocationType type;
  final double? latitude;
  final double? longitude;
  final String? county;
  final String? city;
  final String? community;
  final String? address;
  final String? description;
  final double? triggerRadius;
  final double? mapVisibilityRadius;
  final int priority;
  final List<String> narrationIds;
  final List<String> audioFiles;
  final List<String> images;
  final List<String> videos;
  final List<String> relatedLocations;
  final bool active;
  final bool featured;
  final bool hidden;
  final String? source;
  final String? sourceId;
  final String? destinationCode;
  final DateTime? updatedAt;
  final DateTime? createdAt;

  // ── Richer PoI fields (county-agnostic; all optional) ──
  final String? state;
  final String? shortDescription;
  final String? longDescription;

  /// The spoken narration script (fed to ElevenLabs / on-device TTS).
  final String? narrationScript;
  final String? hours;
  final String? admission;
  final String? externalWebsite;
  final String? parkingInfo;
  final String? restrooms;
  final String? difficulty;
  final List<String> tags;
  final bool? familyFriendly;
  final bool? petFriendly;
  final bool? wheelchairAccessible;

  // ── GPS trigger configuration (migration 0040) ──
  /// Whether this location should fire its GPS trigger on arrival (entering
  /// [triggerRadius]). Defaults to true — matches the existing behavior
  /// before this column existed (every location triggered on arrival).
  final bool arrivalTrigger;

  /// Whether this location should also fire a trigger on departure (leaving
  /// [triggerRadius]). Defaults to false — opt-in, since most locations only
  /// want an arrival narration today.
  final bool departureTrigger;

  /// When true, the trigger fires at most once ever for this location
  /// (regardless of [cooldownSeconds]).
  final bool playOnce;

  /// Minimum seconds between repeat triggers for this location. Null = no
  /// cooldown enforced (falls back to whatever the trigger engine's own
  /// default is, unchanged from today).
  final int? cooldownSeconds;

  /// Explicit editorial status (migration 0040); null = not yet set by an
  /// admin. Use [effectiveContentStatus] for display/filtering — it supplies
  /// a sensible computed default so untouched rows aren't just blank.
  final ContentStatus? contentStatus;

  /// "Discover This Area" (migration 0041) — how long this area's full
  /// narrated content takes to listen to, shown on the Discover Screen.
  /// Only meaningful for `type == LocationType.area`; null elsewhere.
  final int? estimatedListeningMinutes;

  /// The richest description available (long → plain → short).
  String? get bestDescription {
    for (final s in [longDescription, description, shortDescription]) {
      if ((s ?? '').trim().isNotEmpty) return s!.trim();
    }
    return null;
  }

  bool get hasDescription => bestDescription != null;
  bool get hasTags => tags.any((t) => t.trim().isNotEmpty);

  MasterLocation copyWith({
    List<String>? images,
    List<String>? audioFiles,
    List<String>? narrationIds,
    bool? featured,
    bool? active,
    bool? hidden,
  }) => MasterLocation(
    id: id,
    name: name,
    type: type,
    latitude: latitude,
    longitude: longitude,
    county: county,
    city: city,
    community: community,
    address: address,
    description: description,
    triggerRadius: triggerRadius,
    mapVisibilityRadius: mapVisibilityRadius,
    priority: priority,
    narrationIds: narrationIds ?? this.narrationIds,
    audioFiles: audioFiles ?? this.audioFiles,
    images: images ?? this.images,
    videos: videos,
    relatedLocations: relatedLocations,
    active: active ?? this.active,
    featured: featured ?? this.featured,
    hidden: hidden ?? this.hidden,
    source: source,
    sourceId: sourceId,
    destinationCode: destinationCode,
    updatedAt: updatedAt,
  );

  bool get hasCoordinates =>
      latitude != null &&
      longitude != null &&
      !(latitude == 0 && longitude == 0);

  /// Has playable recorded audio.
  bool get hasAudio => audioFiles.any((u) => u.trim().isNotEmpty);

  /// Has narration (a script/link) or audio.
  bool get hasNarration => narrationIds.isNotEmpty || hasAudio;

  /// Derived readiness — the single gate used by the map, radio, GPS & search.
  LocationStatus get status {
    if (!active || hidden) return LocationStatus.disabled;
    return hasAudio ? LocationStatus.ready : LocationStatus.pending;
  }

  bool get isReady => status == LocationStatus.ready;
  bool get isPending => status == LocationStatus.pending;

  /// The editorial workflow status to show/filter by: the explicit
  /// [contentStatus] if an admin has set one, otherwise a computed default so
  /// existing/untouched rows still land somewhere sensible in the workflow.
  /// Deliberately defaults a fully-ready row to [ContentStatus.needsReview]
  /// rather than [ContentStatus.published] — publishing is an editorial
  /// decision this doesn't make on an admin's behalf.
  ContentStatus get effectiveContentStatus {
    if (contentStatus != null) return contentStatus!;
    if (!active || hidden) return ContentStatus.archived;
    if (!hasCoordinates) return ContentStatus.needsGpsVerification;
    if (images.isEmpty) return ContentStatus.needsImages;
    if (!hasNarration) return ContentStatus.needsNarration;
    return ContentStatus.needsReview;
  }

  String? get placeLine {
    final parts = [
      city ?? community,
      county == null ? null : '$county County',
    ].whereType<String>().where((s) => s.trim().isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static double? _d(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v');
  static List<String> _strs(dynamic v) => v is List
      ? v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
      : const [];

  factory MasterLocation.fromJson(Map<String, dynamic> j) => MasterLocation(
    id: (j['id'] ?? '').toString(),
    name: (j['name'] ?? '') as String,
    type: LocationType.fromId(j['category'] as String?),
    latitude: _d(j['latitude']),
    longitude: _d(j['longitude']),
    county: j['county'] as String?,
    city: j['city'] as String?,
    community: j['community'] as String?,
    address: j['address'] as String?,
    description: j['description'] as String?,
    triggerRadius: _d(j['trigger_radius']),
    mapVisibilityRadius: _d(j['map_visibility_radius']),
    priority: (j['priority'] as num?)?.toInt() ?? 0,
    narrationIds: _strs(j['narration_ids']),
    audioFiles: _strs(j['audio_files']),
    images: _strs(j['images']),
    videos: _strs(j['videos']),
    relatedLocations: _strs(j['related_locations']),
    active: (j['active'] ?? true) as bool,
    featured: (j['featured'] ?? false) as bool,
    hidden: (j['hidden'] ?? false) as bool,
    source: j['source'] as String?,
    sourceId: j['source_id']?.toString(),
    destinationCode: j['destination_code'] as String?,
    updatedAt: DateTime.tryParse('${j['updated_at']}'),
    createdAt: DateTime.tryParse('${j['created_at']}'),
    state: j['state'] as String?,
    shortDescription: j['short_description'] as String?,
    longDescription: j['long_description'] as String?,
    narrationScript: j['narration_script'] as String?,
    hours: j['hours'] as String?,
    admission: j['admission'] as String?,
    externalWebsite: j['external_website'] as String?,
    parkingInfo: j['parking_info'] as String?,
    restrooms: j['restrooms'] as String?,
    difficulty: j['difficulty'] as String?,
    tags: _strs(j['tags']),
    familyFriendly: j['family_friendly'] as bool?,
    petFriendly: j['pet_friendly'] as bool?,
    wheelchairAccessible: j['wheelchair_accessible'] as bool?,
    arrivalTrigger: (j['arrival_trigger'] ?? true) as bool,
    departureTrigger: (j['departure_trigger'] ?? false) as bool,
    playOnce: (j['play_once'] ?? false) as bool,
    cooldownSeconds: (j['cooldown_seconds'] as num?)?.toInt(),
    contentStatus: ContentStatus.fromId(j['content_status'] as String?),
    estimatedListeningMinutes:
        (j['estimated_listening_minutes'] as num?)?.toInt(),
  );

  /// Column map for insert/update (id/timestamps/provenance managed elsewhere).
  Map<String, dynamic> toWrite() => {
    'name': name,
    'category': type.id,
    'latitude': latitude,
    'longitude': longitude,
    'county': county,
    'city': city,
    'community': community,
    'address': address,
    'description': description,
    'trigger_radius': triggerRadius,
    'map_visibility_radius': mapVisibilityRadius,
    'priority': priority,
    'narration_ids': narrationIds,
    'audio_files': audioFiles,
    'images': images,
    'videos': videos,
    'related_locations': relatedLocations,
    'active': active,
    'featured': featured,
    'hidden': hidden,
    'state': state,
    'short_description': shortDescription,
    'long_description': longDescription,
    'narration_script': narrationScript,
    'hours': hours,
    'admission': admission,
    'external_website': externalWebsite,
    'parking_info': parkingInfo,
    'restrooms': restrooms,
    'difficulty': difficulty,
    'tags': tags,
    'family_friendly': familyFriendly,
    'pet_friendly': petFriendly,
    'wheelchair_accessible': wheelchairAccessible,
    'arrival_trigger': arrivalTrigger,
    'departure_trigger': departureTrigger,
    'play_once': playOnce,
    'cooldown_seconds': cooldownSeconds,
    'content_status': contentStatus?.id,
    'estimated_listening_minutes': estimatedListeningMinutes,
  };
}
