import 'package:flutter/material.dart';

/// One selectable interest on the Discover interests screen. [token] is
/// stable and used for storage (`profiles.interests`) and scoring — never
/// the display label, so relabeling later is safe.
class DiscoverInterest {
  const DiscoverInterest(this.token, this.label, this.icon);
  final String token;
  final String label;
  final IconData icon;
}

/// The fixed interest taxonomy from the spec. Order here is display order.
const List<DiscoverInterest> discoverInterests = [
  DiscoverInterest('outdoors', 'Outdoors', Icons.terrain_rounded),
  DiscoverInterest('springs_water', 'Springs & Water', Icons.water_drop_rounded),
  DiscoverInterest('hiking_trails', 'Hiking & Trails', Icons.hiking_rounded),
  DiscoverInterest('wildlife', 'Wildlife', Icons.pets_rounded),
  DiscoverInterest('birds', 'Birds', Icons.flutter_dash_rounded),
  DiscoverInterest('plants', 'Plants', Icons.local_florist_rounded),
  DiscoverInterest('history', 'History', Icons.history_edu_rounded),
  DiscoverInterest('arts_culture', 'Arts & Culture', Icons.palette_rounded),
  DiscoverInterest('live_music', 'Live Music', Icons.music_note_rounded),
  DiscoverInterest('festivals', 'Festivals', Icons.celebration_rounded),
  DiscoverInterest('cars_trucks', 'Cars & Trucks', Icons.directions_car_rounded),
  DiscoverInterest('horses_equestrian', 'Horses & Equestrian', Icons.emoji_nature_rounded),
  DiscoverInterest('family', 'Family', Icons.family_restroom_rounded),
  DiscoverInterest('kids', 'Kids', Icons.child_friendly_rounded),
  DiscoverInterest('shopping', 'Shopping', Icons.shopping_bag_rounded),
  DiscoverInterest('markets', 'Markets', Icons.storefront_rounded),
  DiscoverInterest('free_things', 'Free Things', Icons.money_off_rounded),
  DiscoverInterest('nightlife', 'Nightlife', Icons.nightlife_rounded),
  DiscoverInterest('photography', 'Photography', Icons.camera_alt_rounded),
  DiscoverInterest('fishing', 'Fishing', Icons.phishing_rounded),
  DiscoverInterest('boating', 'Boating', Icons.directions_boat_rounded),
  DiscoverInterest('adventure', 'Adventure', Icons.landscape_rounded),
  DiscoverInterest('local_events', 'Local Events', Icons.event_rounded),
];

final Map<String, DiscoverInterest> discoverInterestsByToken = {
  for (final i in discoverInterests) i.token: i,
};

String discoverInterestLabel(String token) =>
    discoverInterestsByToken[token]?.label ?? token;
