/// A local event (migration 0043) — the highest-priority tier in the
/// location-aware player (EVENT > PARK > SPRING > TOWN > COUNTY).
class LocalEvent {
  const LocalEvent({
    required this.id,
    required this.name,
    this.description,
    this.shortDescription,
    this.imageUrl,
    this.latitude,
    this.longitude,
    this.locationId,
    this.county,
    this.city,
    this.eventDate,
    this.startTime,
    this.endTime,
    this.externalWebsite,
    this.active = true,
    this.category,
    this.interestTags = const [],
    this.costInfo,
    this.registrationUrl,
    this.ticketUrl,
    this.phone,
    this.accessibilityInfo,
    this.familyFriendly,
  });

  final String id;
  final String name;
  final String? description;
  final String? shortDescription;
  final String? imageUrl;
  final double? latitude;
  final double? longitude;

  /// Optional link to the master `locations` row this event is happening at.
  final String? locationId;
  final String? county;
  final String? city;
  final DateTime? eventDate;

  /// Raw `HH:MM:SS` (Postgres `time`) strings — formatted for display by the UI.
  final String? startTime;
  final String? endTime;
  final String? externalWebsite;
  final bool active;

  /// Discover Marion County fields (migration 0053) — all optional; admin
  /// tagging is a future step, so these are commonly empty today. See
  /// `interestTagsForEvent` for the keyword-heuristic fallback used until
  /// then.
  final String? category;
  final List<String> interestTags;
  final String? costInfo;
  final String? registrationUrl;
  final String? ticketUrl;
  final String? phone;
  final String? accessibilityInfo;
  final bool? familyFriendly;

  bool get hasCoordinates =>
      latitude != null && longitude != null && !(latitude == 0 && longitude == 0);

  /// The richest description available (long → short).
  String? get bestDescription {
    for (final s in [description, shortDescription]) {
      if ((s ?? '').trim().isNotEmpty) return s!.trim();
    }
    return null;
  }

  static double? _d(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
  static List<String> _strs(dynamic v) =>
      v is List ? v.map((e) => e.toString()).toList() : const [];

  factory LocalEvent.fromJson(Map<String, dynamic> j) => LocalEvent(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '') as String,
        description: j['description'] as String?,
        shortDescription: j['short_description'] as String?,
        imageUrl: j['image_url'] as String?,
        latitude: _d(j['latitude']),
        longitude: _d(j['longitude']),
        locationId: j['location_id']?.toString(),
        county: j['county'] as String?,
        city: j['city'] as String?,
        eventDate: j['event_date'] == null
            ? null
            : DateTime.tryParse(j['event_date'].toString()),
        startTime: j['start_time'] as String?,
        endTime: j['end_time'] as String?,
        externalWebsite: j['external_website'] as String?,
        active: (j['active'] ?? true) as bool,
        category: j['category'] as String?,
        interestTags: _strs(j['interest_tags']),
        costInfo: j['cost_info'] as String?,
        registrationUrl: j['registration_url'] as String?,
        ticketUrl: j['ticket_url'] as String?,
        phone: j['phone'] as String?,
        accessibilityInfo: j['accessibility_info'] as String?,
        familyFriendly: j['family_friendly'] as bool?,
      );
}
