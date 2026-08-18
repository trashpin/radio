/// Strongly-typed route table for ExplorerOS.
///
/// Using an enum instead of raw path strings ("/home", "/map"…) prevents typos
/// and makes navigation refactors safe. The bottom-navigation tabs (see
/// AppShell/AppRouter) are exactly: radio, map, wildlife, more. The rest are
/// pushed detail routes.
enum AppRoute {
  aroundMe('/around-me'),
  home('/home'),
  radio('/radio'),
  aiRanger('/ai-ranger'),
  stories('/stories'),
  map('/map'),
  more('/more'),

  // Authentication (outside the tab shell).
  welcome('/welcome'),
  signIn('/sign-in'),
  createAccount('/create-account'),
  forgotPassword('/forgot-password'),

  // Pushed routes (reachable from Home / the More tab / detail links).
  explorerMode('/explorer-mode'),
  iSeeSomething('/i-see-something'),
  localGems('/local-gems'),
  tellMeMore('/tell-me-more'),
  stationSelect('/station-select'),
  discover('/discover'),
  discoverArea('/discover-area'),
  nearbyPlaces('/nearby-places'),
  explore('/explore'),
  profile('/profile'),
  settings('/settings'),
  downloads('/downloads'),
  wildlife('/wildlife'),
  gps('/gps'),
  radioDirector('/radio-director'),
  programmingDirector('/programming-director'),
  destinationDetails('/destination/:id');

  const AppRoute(this.path);
  final String path;

  /// Builds the concrete details path for a given destination id, e.g.
  /// `AppRoute.destinationDetails.pathFor('42')` → `/destination/42`.
  String pathFor(String id) => '/destination/$id';
}
