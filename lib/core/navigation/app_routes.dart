/// Strongly-typed route table for ExplorerOS.
///
/// Using an enum instead of raw path strings ("/home", "/map"…) prevents typos
/// and makes navigation refactors safe. The first five are bottom-navigation
/// tabs; the rest are pushed detail routes (prepared for upcoming features so
/// the dashboard can already link to them).
enum AppRoute {
  // Bottom-navigation tabs (order matches the nav bar): Home, Radio, AI Ranger,
  // Stories, Map, More.
  home('/home'),
  radio('/radio'),
  aiRanger('/ai-ranger'),
  stories('/stories'),
  map('/map'),
  more('/more'),

  // Pushed routes (reachable from Home / the More tab / detail links).
  discover('/discover'),
  explore('/explore'),
  profile('/profile'),
  settings('/settings'),
  downloads('/downloads'),
  wildlife('/wildlife'),
  gps('/gps'),
  destinationDetails('/destination/:id');

  const AppRoute(this.path);
  final String path;

  /// Builds the concrete details path for a given destination id, e.g.
  /// `AppRoute.destinationDetails.pathFor('42')` → `/destination/42`.
  String pathFor(String id) => '/destination/$id';
}
