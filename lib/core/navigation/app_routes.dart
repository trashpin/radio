/// Strongly-typed route table for ExplorerOS.
///
/// Using an enum instead of raw path strings ("/home", "/map"…) prevents typos
/// and makes navigation refactors safe. The app is Adventure-first — Marion
/// County Adventures is the primary purpose, everything else is a supporting
/// system. The bottom-navigation tabs (see AppShell/AppRouter) are exactly:
/// missionsHome ("Adventures" — the adventure storefront/landing screen),
/// map ("Map" — the active adventure's game board, or the general explore
/// map when none is active), myDiscoveries ("My Discoveries" — the player's
/// journal). Radio, discoverHome, and everything else are one tap away via
/// the More screen (reachable from a menu button on each primary screen).
enum AppRoute {
  aroundMe('/around-me'),
  home('/home'),
  radio('/radio'),
  discoverHome('/discover-home'),
  aiRanger('/ai-ranger'),
  stories('/stories'),
  map('/map'),
  myDiscoveries('/my-discoveries'),
  more('/more'),
  // A Nature & Parks/Springs & Water/etc. browsing feed — kept exactly as it
  // was, relabeled "Places & Categories", reached from More.
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
  // No longer a primary tab (see [AppRoute.radio], the pushed route now
  // used everywhere) — kept defined but unreferenced rather than removed,
  // to avoid churn beyond this navigation pass.
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
  // THE GUIDE — the permanent, game-wide introduction character (distinct
  // from any adventure's own storytelling characters). First-time auto-
  // launch and REPLAY GUIDE both push here.
  guideIntro('/guide-intro'),
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
