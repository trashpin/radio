import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/radio/repositories/radio_station_repository.dart';
import 'package:explorer_os_mobile/shared/models/radio_station.dart';

/// A station's presentation extras (genre + accent) keyed by station id, used
/// by the Stations grid. Kept separate from the [RadioStation] data model.
class StationStyle {
  const StationStyle(this.genre, this.accent, this.icon);
  final String genre;
  final Color accent;
  final IconData icon;
}

const stationStyles = <String, StationStyle>{
  'country': StationStyle('Country', Color(0xFFEE7B2E), Icons.landscape_rounded),
  'rock': StationStyle('Rock', Color(0xFFB5453B), Icons.terrain_rounded),
  'hits': StationStyle('Top Hits', Color(0xFF2C6E8F), Icons.graphic_eq_rounded),
  'kids': StationStyle('Kids Time', Color(0xFF3E9B78), Icons.child_care_rounded),
};

StationStyle styleFor(RadioStation station) =>
    stationStyles[station.id] ??
    StationStyle(station.description ?? 'Radio', const Color(0xFFEE7B2E),
        Icons.radio_rounded);

/// Curated default stations used when the backend `radio_stations` table is
/// empty/absent. Matches the four flagship stations.
const stationCatalog = <RadioStation>[
  RadioStation(
    id: 'country',
    name: 'Country Roads Radio',
    description: 'Where the Journey Meets the Music',
    imageUrl: 'https://images.unsplash.com/photo-1470114716159-e389f8712fda?w=800',
  ),
  RadioStation(
    id: 'rock',
    name: 'Rock Trails Radio',
    description: 'Turn it up on the trail',
    imageUrl: 'https://images.unsplash.com/photo-1519681393784-d120267933ba?w=800',
  ),
  RadioStation(
    id: 'hits',
    name: "Today's Hits Radio",
    description: 'The soundtrack of right now',
    imageUrl: 'https://images.unsplash.com/photo-1470229722913-7c0e2dbbafd3?w=800',
  ),
  RadioStation(
    id: 'kids',
    name: 'Kids Adventure Radio',
    description: 'Songs and stories for young explorers',
    imageUrl: 'https://images.unsplash.com/photo-1503919545889-aef636e10ad4?w=800',
  ),
];

/// Loads stations dynamically from Supabase `radio_stations`; falls back to the
/// curated [stationCatalog] when the table is empty or not yet created.
final radioStationCatalogProvider = FutureProvider<List<RadioStation>>((ref) async {
  try {
    final rows = await ref.watch(radioStationRepositoryProvider).getAll();
    if (rows.isNotEmpty) return rows;
  } catch (_) {
    // table missing / offline → fall through to curated defaults
  }
  return stationCatalog;
});

/// The station the user has chosen (null → the session picks a default).
final selectedStationProvider =
    NotifierProvider<SelectedStation, RadioStation?>(SelectedStation.new);

class SelectedStation extends Notifier<RadioStation?> {
  @override
  RadioStation? build() => null;

  void select(RadioStation station) => state = station;
}
