// TEMPORARY demo entrypoint for the Admin — NOT committed. Seeds sample data via
// provider overrides so the dashboard + pages render without a live Supabase
// (browser reads need the sb_publishable_ key). Real entrypoint: main_admin.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/admin/admin_app.dart';
import 'package:explorer_os_mobile/features/admin/admin_connection.dart';
import 'package:explorer_os_mobile/features/admin/admin_stats.dart';
import 'package:explorer_os_mobile/features/destinations/providers/destinations_provider.dart';
import 'package:explorer_os_mobile/features/discovery/data/species_repository.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';
import 'package:explorer_os_mobile/features/maps/data/admin_map_repository.dart';
import 'package:explorer_os_mobile/features/maps/models/map_poi.dart';
import 'package:explorer_os_mobile/features/media/models/media_item.dart';
import 'package:explorer_os_mobile/shared/models/destination.dart';
import 'package:explorer_os_mobile/shared/models/story.dart';

const _destinations = [
  Destination(
    id: 'ocala',
    name: 'Ocala National Forest',
    description: 'Springs and scrub.',
    location: 'Florida, USA',
    category: 'National Forest',
    featured: true,
    latitude: 29.1872,
    longitude: -81.7137,
  ),
  Destination(
    id: 'everglades',
    name: 'Everglades National Park',
    location: 'Florida, USA',
    category: 'National Park',
    featured: true,
    latitude: 25.2866,
    longitude: -80.8987,
  ),
  Destination(
    id: 'dry-tortugas',
    name: 'Dry Tortugas National Park',
    location: 'Florida, USA',
    category: 'National Park',
    latitude: 24.6285,
    longitude: -82.8732,
  ),
];

const _media = [
  MediaItem(id: 'm1', mediaType: 'audio', title: 'Rolling Through Ocala'),
  MediaItem(id: 'm2', mediaType: 'photo', title: 'Juniper Springs'),
  MediaItem(id: 'm3', mediaType: 'audio', title: 'Juniper Morning'),
  MediaItem(id: 'm4', mediaType: 'video', title: 'Everglades Sunset'),
  MediaItem(id: 'm5', mediaType: 'photo', title: 'Fort Jefferson'),
];

const _stories = [
  Story(
      id: 's1',
      parkId: 'ocala',
      title: 'The Springs of Ocala',
      body: 'How Florida\'s springs formed.'),
  Story(
      id: 's2',
      parkId: 'everglades',
      title: 'River of Grass',
      body: 'The Everglades ecosystem.'),
];

// Ocala plants (seeded so Image Matching demonstrates against a known catalog).
// "Saw Palmetto" already has an image → tests the skip-vs-replace behavior.
const _species = [
  Species(
      id: 'sp1',
      category: 'animals',
      commonName: 'Florida Black Bear',
      scientificName: 'Ursus americanus floridanus',
      description:
          'A subspecies of the American black bear and the largest land mammal in Florida.',
      color: 'black',
      diet: 'omnivore — saw palmetto berries, acorns, insects',
      behavior: 'mostly solitary and shy, active at dawn and dusk',
      conservationStatus: 'least concern',
      safetyInfo: 'never approach or feed bears; store food securely',
      funFacts: 'they can smell food from over a mile away',
      destinationId: 'ocala',
      heroImage: 'https://example.com/bear.jpg'),
  Species(
      id: 'sp2',
      category: 'plants',
      commonName: 'Saw Palmetto',
      scientificName: 'Serenoa repens',
      description:
          'A hardy fan palm that carpets the Florida scrub and pine flatwoods.',
      funFacts: 'individual plants can live for hundreds of years',
      destinationId: 'ocala'),
  Species(id: 'sp3', category: 'plants', commonName: 'Sand Pine', destinationId: 'ocala'),
  Species(id: 'sp4', category: 'birds', commonName: 'Florida Scrub-Jay', scientificName: 'Aphelocoma coerulescens', description: 'The only bird species endemic to Florida.', destinationId: 'ocala'),
  Species(id: 'sp5', category: 'reptiles', commonName: 'Gopher Tortoise', destinationId: 'ocala'),
  Species(id: 'sp6', category: 'plants', commonName: 'Sand Live Oak', destinationId: 'ocala'),
];

// Real Ocala POIs (from Base44) for the Map Editor demo.
MapPoi _poi(String id, String name, String cat, double lat, double lng) =>
    MapPoi(id: id, name: name, category: cat, latitude: lat, longitude: lng,
        parkCode: 'ocala');
final _pois = <MapPoi>[
  _poi('p1', 'Juniper Springs Recreation Area', 'springs', 29.1808, -81.7115),
  _poi('p2', 'Alexander Springs Recreation Area', 'springs', 29.0789, -81.5707),
  _poi('p3', 'Salt Springs Recreation Area', 'springs', 29.3558, -81.7383),
  _poi('p4', 'Silver Glen Springs', 'springs', 29.2461, -81.6442),
  _poi('p5', 'Yearling Trail', 'trailheads', 29.2675, -81.6238),
  _poi('p6', 'Florida National Scenic Trail', 'trailheads', 29.25, -81.70),
  _poi('p7', 'Ocala NF Visitor Center', 'visitor_centers', 29.187, -81.716),
  _poi('p8', 'Pittman Visitor Center', 'visitor_centers', 28.9958, -81.6467),
  _poi('p9', "Pat's Island Homestead", 'historic_sites', 29.1667, -81.7167),
  _poi('p10', 'Fort McCoy Site', 'historic_sites', 29.2475, -81.6492),
  _poi('p11', 'Juniper Springs Campground', 'campgrounds', 29.1805, -81.711),
  _poi('p12', 'Clearwater Lake Recreation Area', 'campgrounds', 28.9792, -81.5511),
  _poi('p13', 'Lake Delancy West', 'campgrounds', 29.4312, -81.7925),
  _poi('p14', 'Pinecastle Overlook', 'scenic_overlooks', 29.01, -81.58),
  _poi('p15', 'Lake George Shoreline', 'scenic_overlooks', 29.2741, -81.5833),
  _poi('p16', 'Hopkins Prairie', 'poi', 29.2755, -81.9035),
  _poi('p17', 'Lake Dorr Recreation Area', 'poi', 29.174, -81.856),
];

const _stats = AdminStats(
  parks: 3,
  locations: 12,
  stories: 5,
  songs: 24,
  wildlife: 8,
  media: 42,
  published: 2,
  drafts: 1,
  pendingReview: 3,
  downloads: 130,
  subscribers: 57,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      overrides: [
        adminConnectionProvider.overrideWith((ref) async =>
            const AdminConnectionReport(
              configured: true,
              url: 'https://qqeyvhcgirmfokoftiuz.supabase.co',
              checks: [
                ConnectionCheck(
                    'destinations', CheckKind.table, true, 'reachable'),
                ConnectionCheck('stops', CheckKind.table, true, 'reachable'),
                ConnectionCheck('stories', CheckKind.table, true, 'reachable'),
                ConnectionCheck('media', CheckKind.table, true, 'reachable'),
                ConnectionCheck(
                    'knowledge_articles', CheckKind.table, true, 'reachable'),
                ConnectionCheck('mp3', CheckKind.bucket, true, 'present'),
              ],
            )),
        adminStatsProvider.overrideWith((ref) async => _stats),
        destinationsProvider.overrideWith((ref) async => _destinations),
        adminMediaProvider.overrideWith((ref) async => _media),
        adminStoriesProvider.overrideWith((ref) async => _stories),
        allSpeciesProvider.overrideWith((ref) async => _species),
        mapEditorPoisProvider.overrideWith((ref) async => _pois),
      ],
      child: const AdminApp(),
    ),
  );
}
