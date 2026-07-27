// TEMPORARY demo entrypoint — NOT committed. Seeds a radio station + playlist so
// the Radio player renders and plays without a live Supabase.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/app/app.dart';
import 'package:explorer_os_mobile/features/destinations/providers/destinations_provider.dart';
import 'package:explorer_os_mobile/features/discovery/data/species_repository.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';
import 'package:explorer_os_mobile/features/maps/models/nearby_item.dart';
import 'package:explorer_os_mobile/features/maps/providers/map_layers_provider.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';
import 'package:explorer_os_mobile/shared/models/stop.dart';
import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/providers/radio_engine_providers.dart';
import 'package:explorer_os_mobile/features/radio/providers/radio_session_provider.dart';
import 'package:explorer_os_mobile/features/radio/providers/stations_provider.dart';
import 'package:explorer_os_mobile/shared/models/destination.dart';
import 'package:explorer_os_mobile/shared/models/radio_station.dart';
import 'package:explorer_os_mobile/shared/models/song.dart';

const _station = RadioStation(
  id: 'station_country',
  name: 'Country Roads Radio',
  destinationId: 'dest_smoky',
  description: 'Where the Journey Meets the Music',
  imageUrl:
      'https://images.unsplash.com/photo-1470114716159-e389f8712fda?w=800',
);

const _songs = [
  Song(
    id: 'song_1',
    stationId: 'station_country',
    title: 'Take Me Home, Country Roads',
    artist: 'John Denver',
    album: 'Poems, Prayers & Promises',
    audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
    durationSeconds: 190,
  ),
  Song(
    id: 'song_2',
    stationId: 'station_country',
    title: 'On the Road Again',
    artist: 'Willie Nelson',
    audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
    durationSeconds: 155,
  ),
  Song(
    id: 'song_3',
    stationId: 'station_country',
    title: 'Life Is a Highway',
    artist: 'Tom Cochrane',
    audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
    durationSeconds: 276,
  ),
];

const _destinations = [
  Destination(
    id: 'dest_smoky',
    name: 'Great Smoky Mountains National Park',
    description: 'Misty ridges and Appalachian forests.',
    location: 'Chimney Tops Rd · Mile 7.4',
    category: 'National Park',
    featured: true,
    latitude: 35.6532,
    longitude: -83.5070,
  ),
  Destination(
    id: 'dest_ocala',
    name: 'Ocala National Forest',
    description: 'Springs, sand pine scrub, and scenic drives.',
    location: 'Florida, USA',
    category: 'National Forest',
    featured: true,
    latitude: 29.1872,
    longitude: -81.7137,
  ),
  Destination(
    id: 'dest_everglades',
    name: 'Everglades National Park',
    description: 'Vast subtropical wilderness.',
    location: 'Florida, USA',
    category: 'National Park',
    latitude: 25.2866,
    longitude: -80.8987,
  ),
  Destination(
    id: 'dest_dry_tortugas',
    name: 'Dry Tortugas National Park',
    description: 'Remote islands and Fort Jefferson.',
    location: 'Florida, USA',
    category: 'National Park',
    latitude: 24.6285,
    longitude: -82.8732,
  ),
];

const _ocalaPlants = [
  Species(
      id: 'p1',
      category: 'plants',
      commonName: 'Saw Palmetto',
      scientificName: 'Serenoa repens',
      heroImage: 'https://images.unsplash.com/photo-1509402308440-1a1f77f7d0f1?w=400'),
  Species(
      id: 'p2',
      category: 'plants',
      commonName: 'Sand Pine',
      scientificName: 'Pinus clausa',
      heroImage: 'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=400'),
  Species(
      id: 'p3',
      category: 'plants',
      commonName: 'Longleaf Pine',
      scientificName: 'Pinus palustris',
      heroImage: 'https://images.unsplash.com/photo-1500382017468-9049fed747ef?w=400'),
  Species(
      id: 'p4',
      category: 'plants',
      commonName: 'Wiregrass',
      scientificName: 'Aristida stricta',
      heroImage: 'https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?w=400'),
  Species(
      id: 'p5',
      category: 'plants',
      commonName: 'Gallberry',
      scientificName: 'Ilex glabra',
      heroImage: 'https://images.unsplash.com/photo-1502082553048-f009c37129b9?w=400'),
  Species(
      id: 'p6',
      category: 'plants',
      commonName: 'Sand Live Oak',
      scientificName: 'Quercus geminata',
      heroImage: 'https://images.unsplash.com/photo-1518495973542-4542c06a5843?w=400'),
];

const _stops = [
  Stop(
      id: 'st1',
      parkId: 'dest_ocala',
      name: 'Juniper Springs',
      stopType: 'Spring',
      latitude: 29.1836,
      longitude: -81.7106),
  Stop(
      id: 'st2',
      parkId: 'dest_ocala',
      name: 'Alexander Springs',
      stopType: 'Spring',
      latitude: 29.0808,
      longitude: -81.5758),
  Stop(
      id: 'st3',
      parkId: 'dest_ocala',
      name: 'Salt Springs',
      stopType: 'Spring',
      latitude: 29.3506,
      longitude: -81.7318),
];

// Ocala-area points across categories for the real-time "Around Me" demo
// (offsets from ~29.1872,-81.7137; ~0.001° ≈ 365 ft).
const _oLat = 29.1872, _oLng = -81.7137;
NearbyItem _n(String id, String cat, String name, double dLat, double dLng,
        {String? img, String? desc}) =>
    NearbyItem(
        id: id,
        category: cat,
        name: name,
        latitude: _oLat + dLat,
        longitude: _oLng + dLng,
        imageUrl: img,
        description: desc);

final _mapLocations = <NearbyItem>[
  _n('n1', 'trees', 'Longleaf Pine', 0.0004, 0.0003,
      desc: 'Fire-adapted pine of the sandhills.'),
  _n('n2', 'mammals', 'White-tailed Deer', 0.0008, -0.0006),
  _n('n3', 'reptiles', 'Gopher Tortoise', 0.0011, 0.0009),
  _n('n4', 'visitor_centers', 'Ocala Visitor Center', -0.0006, -0.0005),
  _n('n5', 'wildflowers', 'Blazing Star', 0.0015, -0.001),
  _n('n6', 'birds', 'Red-shouldered Hawk', 0.003, -0.002),
  _n('n7', 'trails', 'Florida Trail', 0.003, 0.003),
  _n('n8', 'plants', 'Saw Palmetto', 0.002, 0.001),
  _n('n9', 'historic_sites', 'CCC Camp Structure', 0.004, -0.003),
  _n('n10', 'mammals', 'Black Bear', 0.006, 0.004),
  _n('n11', 'scenic_overlooks', 'Lake George Overlook', 0.008, 0.006),
  _n('n12', 'birds', 'Bald Eagle', 0.009, 0.001),
  _n('n13', 'springs', 'Juniper Spring', 0.02, 0.001,
      desc: 'Crystal-clear spring; popular for swimming and paddling.'),
  _n('n14', 'campgrounds', 'Juniper Springs Campground', 0.019, 0.0),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      overrides: [
        destinationsProvider.overrideWith((ref) async => _destinations),
        allStopsProvider.overrideWith((ref) async => _stops),
        mapLocationsProvider.overrideWith((ref) async => _mapLocations),
        speciesByCategoryProvider('plants')
            .overrideWith((ref) async => _ocalaPlants),
        radioSessionProvider.overrideWith((ref) async {
          ref.read(radioAudioServiceProvider); // attach audio adapter
          // Honor a station picked from the Stations screen; keep the seeded
          // playlist so playback stays demoable.
          final station = ref.watch(selectedStationProvider) ?? _station;
          ref
              .read(radioEngineServiceProvider)
              .changeStation(station, songs: _songs, autoPlay: false);
          ref.read(radioEngineControllerProvider);
          return station;
        }),
      ],
      child: const ExplorerApp(),
    ),
  );
}
