import 'package:flutter/material.dart';

/// Categories a user can choose when reporting an observation via
/// "I See Something". Each carries a display [label], a stable [token] (stored
/// in Supabase), and an [icon] used in the picker and on map markers.
enum SightingCategory {
  animal('animal', 'Animal', Icons.cruelty_free_rounded),
  bird('bird', 'Bird', Icons.flutter_dash_rounded),
  plant('plant', 'Plant', Icons.local_florist_rounded),
  tree('tree', 'Tree', Icons.park_rounded),
  wildflower('wildflower', 'Wildflower', Icons.filter_vintage_rounded),
  reptile('reptile', 'Reptile', Icons.pest_control_rounded),
  fish('fish', 'Fish', Icons.set_meal_rounded),
  insect('insect', 'Insect', Icons.bug_report_rounded),
  scenicView('scenic_view', 'Scenic View', Icons.landscape_rounded),
  waterfall('waterfall', 'Waterfall', Icons.water_rounded),
  spring('spring', 'Spring', Icons.water_drop_rounded),
  historicSite('historic_site', 'Historic Site', Icons.account_balance_rounded),
  trailFeature('trail_feature', 'Trail Feature', Icons.signpost_rounded),
  other('other', 'Other', Icons.more_horiz_rounded);

  const SightingCategory(this.token, this.label, this.icon);

  final String token;
  final String label;
  final IconData icon;

  static SightingCategory fromToken(String? token) => values.firstWhere(
        (c) => c.token == token,
        orElse: () => SightingCategory.other,
      );
}
