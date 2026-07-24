/// Strongly-typed route table for ExplorerOS.
///
/// Using an enum instead of raw path strings ("/home", "/map"…) prevents typos
/// and makes navigation refactors safe. The first five are bottom-navigation
/// tabs; the rest are pushed detail routes (prepared for upcoming features so
/// the dashboard can already link to them).
enum AppRoute {
  // Bottom-navigation tabs.
  home('/home'),
  explore('/explore'),
  map('/map'),
  radio('/radio'),
  profile('/profile'),

  // Pushed routes (detail / future features).
  settings('/settings'),
  downloads('/downloads'),
  stories('/stories'),
  wildlife('/wildlife'),
  gps('/gps');

  const AppRoute(this.path);
  final String path;
}
