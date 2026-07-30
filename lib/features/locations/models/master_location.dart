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
  pointOfInterest('point_of_interest', 'Point of Interest');

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
    if (has('community') || has('unincorporated')) return LocationType.community;
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

  MasterLocation copyWith({
    List<String>? images,
    List<String>? audioFiles,
    List<String>? narrationIds,
    bool? featured,
    bool? active,
    bool? hidden,
  }) =>
      MasterLocation(
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
      latitude != null && longitude != null &&
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

  String? get placeLine {
    final parts = [city ?? community, county == null ? null : '$county County']
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .toList();
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static double? _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');
  static List<String> _strs(dynamic v) =>
      v is List ? v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
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
      };
}
