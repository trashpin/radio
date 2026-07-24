// TEMPORARY demo entrypoint — NOT committed.
// Overrides the destinations provider with sample data so the populated Explore
// design can be screenshotted without a live Supabase connection.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/app/app.dart';
import 'package:explorer_os_mobile/features/destinations/providers/destinations_provider.dart';
import 'package:explorer_os_mobile/shared/models/destination.dart';

const _preview = [
  Destination(
    id: '1',
    name: 'Yellowstone National Park',
    location: 'Wyoming, Montana, Idaho',
    category: 'park',
    featured: true,
    imageUrl: 'https://picsum.photos/seed/yellowstone/900/500',
  ),
  Destination(
    id: '2',
    name: 'Silver Springs State Park',
    location: 'Ocala, Florida',
    category: 'park',
    distanceLabel: '12 mi',
    imageUrl: 'https://picsum.photos/seed/silver/300/300',
  ),
  Destination(
    id: '3',
    name: 'Juniper Springs',
    location: 'Ocala National Forest',
    category: 'trail',
    distanceLabel: '18 mi',
    imageUrl: 'https://picsum.photos/seed/juniper/300/300',
  ),
  Destination(
    id: '4',
    name: 'Rainbow Springs State Park',
    location: 'Dunnellon, Florida',
    category: 'park',
    distanceLabel: '22 mi',
    imageUrl: 'https://picsum.photos/seed/rainbow/300/300',
  ),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      overrides: [
        destinationsProvider.overrideWith((ref) async => _preview),
      ],
      child: const ExplorerApp(),
    ),
  );
}
