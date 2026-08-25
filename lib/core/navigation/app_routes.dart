/// Strongly-typed route table for ExplorerOS.
///
/// Using an enum instead of raw path strings ("/home", "/map"…) prevents typos
/// and makes navigation refactors safe. Sunshine Travel Radio is a two-tab
/// experience — the bottom-navigation tabs (see AppShell/AppRouter) are
/// exactly: explore (the radio player — "Listen to Marion County"), and
/// discoverHome ("Find something to do"). Everything else is one tap away
/// via the More screen (reachable from either tab's own menu).
enum AppRoute {
  aroundMe('/around-me'),
  home('/home'),
  radio('/radio'),
  discoverHome('/discover-home'),
  aiRanger('/ai-ranger'),
  stories('/stories'),
  map('/map'),
  more('/more'),
  // The pre-two-tab "Explore" content (a Nature & Parks/Springs & Water/etc.
  // browsing feed) — kept exactly as it was, just relabeled "Places &
  // Categories" and reached from More now that the primary Explore tab is
  // the radio player itself (see AppRoute.explore below).
  placesGuide('/places-guide'),

  // Authentication (outside the tab shell).
  welcome('/welcome'),
  signIn('/sign-in'),
  createAccount('/create-account'),
  forgotPassword('/forgot-password'),

  // Pushed routes (reachable from Home / the More tab / detail links).
  explorerMode('/explorer-mode'),
  iSeeSomething('/i-see-something'),
  whatIsThat('/what-is-that'),
  ocalaForest('/ocala-forest'),
  localGems('/local-gems'),
  tellMeMore('/tell-me-more'),
  stationSelect('/station-select'),
  discover('/discover'),
  discoverArea('/discover-area'),
  nearbyPlaces('/nearby-places'),
  // The primary "Explore" tab — Sunshine Travel Radio itself (RadioScreen).
  // "Explore" as a word now means the audio/listening experience; the old
  // browsing-feed screen that used to live at this path moved to
  // AppRoute.placesGuide above.
  explore('/explore'),
  profile('/profile'),
  settings('/settings'),
  downloads('/downloads'),
  wildlife('/wildlife'),
  gps('/gps'),
  radioDirector('/radio-director'),
  programmingDirector('/programming-director'),
  destinationDetails('/destination/:id'),
  // The push-notification deep link target (spec: "Notification -> Specific
  // Event", never the generic Discover home). Same id-in-path pattern as
  // destinationDetails above.
  discoverEventDetail('/discover-event/:id'),

  // Marion County Adventures (GPS + storytelling + QR exploration game).
  missionsHome('/missions'),
  // The Adventure Introduction (spec: pulled into a story BEFORE any map/
  // GPS/travel begins) — selecting a mission goes here first, never
  // straight to the GPS-tracking player.
  missionIntro('/missions/:id/intro'),
  missionPlayer('/missions/:id'),
  qrScan('/qr-scan'),
  // No id — like missionPuzzle below, reads the current stop's
  // TreasureDiscovery off the already-active ActiveMissionController.
  treasureMap('/treasure-map'),
  oldWorld('/old-world/:id'),
  // No id — reads the pending puzzle off the already-active
  // ActiveMissionController, the same way MissionCompleteScreen already
  // reads its summary from that controller's state.
  missionPuzzle('/mission-puzzle'),
  missionComplete('/mission-complete');

  const AppRoute(this.path);
  final String path;

  /// Builds the concrete details path for a given destination id, e.g.
  /// `AppRoute.destinationDetails.pathFor('42')` → `/destination/42`.
  String pathFor(String id) => '/destination/$id';

  /// `AppRoute.discoverEventDetail.eventPathFor('42')` → `/discover-event/42`.
  String eventPathFor(String id) => '/discover-event/$id';

  /// `AppRoute.missionPlayer.missionPathFor('42')` → `/missions/42`.
  String missionPathFor(String id) => '/missions/$id';

  /// `AppRoute.missionIntro.missionIntroPathFor('42')` → `/missions/42/intro`.
  String missionIntroPathFor(String id) => '/missions/$id/intro';

  /// `AppRoute.oldWorld.oldWorldPathFor('42')` → `/old-world/42`.
  String oldWorldPathFor(String id) => '/old-world/$id';
}
