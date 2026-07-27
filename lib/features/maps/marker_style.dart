import 'package:flutter/material.dart';

import 'package:explorer_os_mobile/features/maps/marker_category_infer.dart';

/// The visual identity of a map marker category — color + icon + label — matching
/// the Map Editor legend. Every destination/POI category on the map is bucketed
/// into one of these so the marker color immediately communicates what it is.
class MarkerCategoryStyle {
  const MarkerCategoryStyle(this.key, this.label, this.color, this.icon);
  final String key;
  final String label;
  final Color color;
  final IconData icon;
}

// Legend (colors identical to the admin Map Editor legend).
const _trailheads = MarkerCategoryStyle(
    'trailheads', 'Trailheads', Color(0xFF43A047), Icons.hiking_rounded);
const _visitorCenters = MarkerCategoryStyle(
    'visitor_centers', 'Visitor Centers', Color(0xFF1E88E5), Icons.info_rounded);
const _historicSites = MarkerCategoryStyle('historic_sites', 'Historic Sites',
    Color(0xFF8E24AA), Icons.account_balance_rounded);
const _wildlife = MarkerCategoryStyle('wildlife_viewing', 'Wildlife Viewing',
    Color(0xFFFDD835), Icons.pets_rounded);
const _safety = MarkerCategoryStyle('safety_alerts', 'Safety Alerts',
    Color(0xFFE53935), Icons.warning_amber_rounded);
const _campgrounds = MarkerCategoryStyle(
    'campgrounds', 'Campgrounds', Color(0xFFFB8C00), Icons.cabin_rounded);
const _parking = MarkerCategoryStyle(
    'parking', 'Parking', Color(0xFF90A4AE), Icons.local_parking_rounded);
const _springs = MarkerCategoryStyle(
    'springs', 'Springs', Color(0xFF00ACC1), Icons.water_drop_rounded);
const _scenic = MarkerCategoryStyle('scenic_overlooks', 'Scenic Overlooks',
    Color(0xFF2E7D32), Icons.landscape_rounded);
const _cities = MarkerCategoryStyle(
    'cities', 'Cities', Color(0xFF3949AB), Icons.location_city_rounded);
const _other =
    MarkerCategoryStyle('other', 'Other', Color(0xFF9E9E9E), Icons.place_rounded);

/// A park/destination (not in the legend, but plotted on the map).
const parkMarkerStyle =
    MarkerCategoryStyle('park', 'Park', Color(0xFF2E9E6B), Icons.forest_rounded);

/// The legend, in display order.
const markerLegend = <MarkerCategoryStyle>[
  _trailheads,
  _visitorCenters,
  _historicSites,
  _wildlife,
  _safety,
  _campgrounds,
  _parking,
  _springs,
  _scenic,
  _cities,
  _other,
];

/// The legend style for a category key (as produced by [inferCategoryKey]).
final Map<String, MarkerCategoryStyle> _byKey = {
  for (final s in markerLegend) s.key: s,
};

/// Style for a POI using both its [category] and its [name] (and optional
/// [subcategory]): honors an explicit legend category, otherwise infers one
/// from the name so pins are colored even when the stored category is generic
/// or null. This is what the map uses for markers.
MarkerCategoryStyle markerStyleForItem(String? category, String? name,
        [String? subcategory]) =>
    _byKey[inferCategoryKey(category, name, subcategory)] ?? _other;

/// Buckets any raw category token (from `map_locations`, sightings, or a
/// destination type) into one of the legend categories.
MarkerCategoryStyle markerStyleFor(String? rawCategory) {
  switch ((rawCategory ?? '').toLowerCase().trim()) {
    case 'trailheads':
    case 'trailhead':
    case 'trails':
    case 'trail':
    case 'trail_features':
      return _trailheads;
    case 'visitor_centers':
    case 'visitor_center':
    case 'ranger_stations':
    case 'ranger_station':
      return _visitorCenters;
    case 'historic_sites':
    case 'historic_site':
    case 'historical_events':
    case 'history':
      return _historicSites;
    case 'wildlife_viewing':
    case 'wildlife':
    case 'mammals':
    case 'birds':
    case 'reptiles':
    case 'amphibians':
    case 'fish':
    case 'insects':
      return _wildlife;
    case 'safety_alerts':
    case 'safety':
    case 'hazard':
    case 'alert':
      return _safety;
    case 'campgrounds':
    case 'campground':
    case 'camping':
      return _campgrounds;
    case 'parking':
    case 'parking_areas':
      return _parking;
    case 'springs':
    case 'spring':
    case 'waterfalls':
    case 'boat_ramps':
    case 'fishing_areas':
      return _springs;
    case 'scenic_overlooks':
    case 'scenic_overlook':
    case 'scenic_views':
    case 'overlook':
      return _scenic;
    default:
      return _other;
  }
}
