import 'package:explorer_os_mobile/features/locations/active_location_types.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

/// OpenStreetMap / Overpass API adapter — the first import source for the
/// nationwide pipeline. Free, worldwide, and covers nearly every ExplorerOS
/// location type. This file is PURE (query building + JSON→MasterLocation
/// mapping) so it's fully unit-testable without a network; [LocationImportService]
/// performs the actual HTTP fetch + dedupe + upsert.
class OsmOverpass {
  const OsmOverpass._();

  static const String source = 'osm';
  static const String endpoint = 'https://overpass-api.de/api/interpreter';

  /// Overpass QL for every ExplorerOS-relevant feature inside a bounding box
  /// [south,west,north,east]. Uses `out center` so ways/relations return a
  /// representative point. Only named features are kept (see [parse]).
  static String query({
    required double south,
    required double west,
    required double north,
    required double east,
    int timeoutSeconds = 60,
  }) {
    final bbox = '($south,$west,$north,$east)';
    // Scoped to the FIVE active tiers only (see active_location_types.dart):
    // cities/communities, city parks, and springs. (County + Florida State
    // Parks are curated from trusted government sources, not this importer;
    // businesses/POIs are intentionally excluded.) `nwr` = nodes+ways+relations.
    const selectors = [
      'place~"city|town|village|hamlet|suburb|neighbourhood"',
      'leisure~"park|garden"',
      'natural~"spring"',
    ];
    final body = selectors.map((s) => 'nwr[$s]$bbox;').join('\n  ');
    return '[out:json][timeout:$timeoutSeconds];\n(\n  $body\n);\nout center tags;';
  }

  /// Parse an Overpass JSON response into importable locations. Skips elements
  /// without a name or a resolvable coordinate. [state]/[county] are stamped on
  /// each row when the caller knows the scope (helps hierarchy + filters).
  static List<MasterLocation> parse(
    Map<String, dynamic> json, {
    String? state,
    String? county,
  }) {
    final elements = (json['elements'] as List?) ?? const [];
    final out = <MasterLocation>[];
    for (final e in elements) {
      if (e is! Map) continue;
      final tags = (e['tags'] as Map?)?.cast<String, dynamic>() ?? const {};
      final name = (tags['name'] as String?)?.trim();
      if (name == null || name.isEmpty) continue;

      final type = _typeForTags(tags);
      if (type == null || !isActiveLocationType(type)) continue;

      final coord = _coord(e);
      if (coord == null) continue;

      final osmType = (e['type'] ?? 'node').toString();
      final osmId = (e['id'] ?? '').toString();
      if (osmId.isEmpty) continue;

      out.add(MasterLocation(
        id: '', // new — DB generates on insert; matched on (source, source_id)
        name: name,
        type: type,
        latitude: coord.$1,
        longitude: coord.$2,
        state: state,
        county: (tags['addr:county'] as String?)?.trim() ?? county,
        city: (tags['addr:city'] as String?)?.trim(),
        address: _address(tags),
        externalWebsite: _first(tags,
            ['website', 'contact:website', 'url', 'wikipedia']),
        phone: _first(tags, ['phone', 'contact:phone']),
        hours: (tags['opening_hours'] as String?)?.trim(),
        source: source,
        sourceId: '$osmType/$osmId',
        // Imported rows start unpublished/pending review; nothing is shown to
        // users until an admin (or the AI+approval pipeline) publishes it.
        active: true,
        contentStatus: ContentStatus.draft,
      ));
    }
    return out;
  }

  // ── OSM tags → LocationType (null = ignore this element) ──
  static LocationType? _typeForTags(Map<String, dynamic> t) {
    String? tag(String k) => (t[k] as String?)?.toLowerCase().trim();
    final place = tag('place');
    if (place != null) {
      switch (place) {
        case 'city':
          return LocationType.city;
        case 'town':
          return LocationType.town;
        case 'village':
        case 'hamlet':
          return LocationType.village;
        case 'suburb':
        case 'neighbourhood':
          return LocationType.neighborhood;
      }
    }
    final boundary = tag('boundary');
    if (boundary == 'national_park') return LocationType.nationalPark;
    if (boundary == 'protected_area') return LocationType.wildlifeManagementArea;

    final natural = tag('natural');
    if (natural == 'waterfall') return LocationType.waterfall;
    if (natural == 'beach') return LocationType.beach;
    if (natural == 'cave_entrance') return LocationType.cave;
    if (natural == 'spring') return LocationType.spring;
    if (natural == 'peak') return LocationType.scenicOverlook;
    if (tag('waterway') == 'waterfall') return LocationType.waterfall;

    final manMade = tag('man_made');
    if (manMade == 'lighthouse') return LocationType.lighthouse;
    if (manMade == 'bridge') return LocationType.bridge;

    final historic = tag('historic');
    if (historic != null) {
      switch (historic) {
        case 'monument':
          return LocationType.monument;
        case 'memorial':
          return LocationType.memorial;
        default:
          return LocationType.historicSite;
      }
    }

    final tourism = tag('tourism');
    if (tourism != null) {
      switch (tourism) {
        case 'museum':
        case 'gallery':
          return LocationType.museum;
        case 'viewpoint':
          return LocationType.scenicOverlook;
        case 'camp_site':
          return LocationType.campground;
        case 'information':
          return LocationType.visitorCenter;
        case 'artwork':
        case 'attraction':
          return LocationType.attraction;
      }
    }

    final leisure = tag('leisure');
    if (leisure == 'park' || leisure == 'garden') return LocationType.cityPark;
    if (leisure == 'nature_reserve') {
      return LocationType.wildlifeManagementArea;
    }

    final amenity = tag('amenity');
    if (amenity == 'restaurant' || amenity == 'fast_food') {
      return LocationType.restaurant;
    }
    if (amenity == 'cafe') return LocationType.coffeeShop;
    if (amenity == 'theatre' || amenity == 'arts_centre') {
      return LocationType.eventVenue;
    }
    return null;
  }

  static (double, double)? _coord(Map e) {
    final lat = e['lat'] ?? (e['center'] is Map ? e['center']['lat'] : null);
    final lon = e['lon'] ?? (e['center'] is Map ? e['center']['lon'] : null);
    final la = lat is num ? lat.toDouble() : double.tryParse('${lat ?? ''}');
    final lo = lon is num ? lon.toDouble() : double.tryParse('${lon ?? ''}');
    if (la == null || lo == null) return null;
    return (la, lo);
  }

  static String? _first(Map<String, dynamic> t, List<String> keys) {
    for (final k in keys) {
      final v = (t[k] as String?)?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  static String? _address(Map<String, dynamic> t) {
    final parts = [
      [t['addr:housenumber'], t['addr:street']]
          .whereType<String>()
          .join(' ')
          .trim(),
      (t['addr:city'] as String?)?.trim(),
      (t['addr:state'] as String?)?.trim(),
      (t['addr:postcode'] as String?)?.trim(),
    ].where((p) => p != null && p.toString().trim().isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
  }
}
