import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Sidebar groupings for the admin modules.
enum AdminGroup {
  overview('Overview'),
  mediaImports('Media & Imports'),
  content('Locations'),
  audio('Radio'),
  nature('Nature'),
  assets('Assets'),
  platform('Platform');

  const AdminGroup(this.label);
  final String label;
}

/// The full admin module catalog (sidebar entries).
///
/// [ready] modules render real, data-backed pages; [ready]-false modules render
/// a consistent placeholder describing scope + the backing table, so the whole
/// information architecture is navigable now and each page is a one-line swap
/// later.
///
/// Simplified per the 2026 admin-panel audit: 10 never-built placeholder
/// modules whose scope was already covered elsewhere were removed outright
/// (Locations/stops, Trails, Routes, Historical Events, Explorer Radio,
/// Albums, Wildlife, Plants, Birds, AI Content). 8 more modules were folded
/// into a sibling page as a tab rather than staying separate top-level nav
/// entries — see each surviving module's doc comment for what it absorbed.
/// Nothing was deleted that had a real, working page; every fold-in kept the
/// original page's code, just nested instead of top-level.
enum AdminModule {
  dashboard('Dashboard', Icons.dashboard_rounded, AdminGroup.overview,
      ready: true),

  mediaImports('Media & Imports', Icons.drive_folder_upload_rounded,
      AdminGroup.mediaImports,
      ready: true,
      description: 'Upload media to storage, manage songs, import CSVs, '
          'browse files, and manage narration. NOTE: overlaps with Media '
          'Manager/Music Library/Narration — flagged in the admin audit for a '
          'closer look at what (if anything) is still uniquely here.'),

  masterLocations('Master Locations', Icons.hub_rounded, AdminGroup.content,
      ready: true,
      description: 'The ONE location database. Every place exists once and '
          'powers the map, radio, GPS triggers, nearby, narration, and '
          'search. Includes a Location Content tab — the GPS-narration '
          'library the Location Intelligence Engine reads at runtime (kept '
          'as its own live table; only the admin editing screen moved here).',
      table: 'locations'),
  destinations('Destinations', Icons.travel_explore_rounded, AdminGroup.content,
      ready: true,
      description: 'Master destination system: AI content status, filters, '
          'per-destination AI jobs, and scalable destination codes. Parks '
          'folded in as a filtered view (same table, no separate page).',
      table: 'destinations'),
  mapEditor('Legacy Map Editor', Icons.edit_location_alt_rounded,
      AdminGroup.content,
      ready: true,
      description: 'Click-to-create locations, drag markers, trigger radius. '
          'Writes to the legacy map_locations table (pre-dates Master '
          'Locations) — kept working, relabeled so it is clearly the old '
          'path until its click-to-create UX is ported to Master Locations.',
      table: 'map_locations'),
  stories('Stories', Icons.menu_book_rounded, AdminGroup.content,
      ready: true,
      description: 'Narrations, scripts, GPS triggers.',
      table: 'stories'),
  storyStudio('Story Studio', Icons.auto_stories_rounded, AdminGroup.content,
      ready: true,
      description: 'AI story production: generate, review, voice, and '
          'GPS-trigger educational stories.',
      table: 'story_library'),
  contentGenerator('Destination Content Generator', Icons.hub_rounded,
      AdminGroup.content,
      ready: true,
      description: 'Master content engine for the Destinations pipeline: '
          'research destinations, build a knowledge base, and queue story/'
          'audio jobs at scale.',
      table: 'generation_jobs'),
  countyManager('County Manager', Icons.map_rounded, AdminGroup.content,
      ready: true,
      description: 'County welcome greetings, weather reports & recommendations '
          'for the travel-radio county reports.',
      table: 'counties'),
  categoryManager('Category Manager', Icons.category_rounded,
      AdminGroup.content,
      ready: true,
      description: 'Every category a location can be assigned — seeded with '
          'the built-in taxonomy, plus unlimited custom categories an admin '
          'adds. Immediately assignable in Master Locations, no app update '
          'required.',
      table: 'categories'),
  countyCompletionDashboard('County Completion Dashboard',
      Icons.fact_check_rounded, AdminGroup.content,
      ready: true,
      description: 'Content readiness per county — cities, communities, '
          'attractions, museums/parks/trails/hidden gems complete, narration/'
          'image/GPS coverage, and an overall completion percentage. '
          'Filterable by county.',
      table: 'locations'),
  nearbyGems('Nearby Gems Manager', Icons.diamond_rounded, AdminGroup.content,
      ready: true,
      description: 'The ONLY source of Nearby Gems shown to users — admin-'
          'curated (name, badge, images, GPS, narration, active). No Google '
          'Places / third-party import.',
      table: 'nearby_gems'),
  locationTester('Location Tester', Icons.wrong_location_rounded,
      AdminGroup.content,
      ready: true,
      description: 'Enter any GPS coordinate + radius and see exactly what a '
          'user would get there: every master location with its live distance '
          'and the precise accept/reject reason from the Location Engine — no '
          'device or driving required.',
      table: 'locations'),

  musicLibrary('Music Library', Icons.library_music_rounded, AdminGroup.audio,
      ready: true,
      description: 'Upload songs (audio + artwork) straight to Supabase.',
      table: 'songs'),

  audioProduction('Audio Production Studio', Icons.graphic_eq_rounded,
      AdminGroup.audio,
      ready: true,
      description: 'Dashboard, production queue, voice library, audio '
          'library, batch generator, audit, settings, Narration, and Audio '
          'Recall — one home for narration across every record (absorbed '
          'the former standalone Narration Studio and Audio Recall pages as '
          'tabs).',
      table: 'audio_assets'),
  safetyMessages('Safety Messages', Icons.health_and_safety_rounded,
      AdminGroup.audio,
      ready: true,
      description: 'Safety announcements the radio can interrupt with.',
      table: 'safety_messages'),
  programmingSchedule('Programming Schedule', Icons.schedule_rounded,
      AdminGroup.audio,
      ready: true,
      description: 'Rules for what plays when (announcements between songs).',
      table: 'radio_schedule'),
  djStudio('DJ Studio', Icons.headset_mic_rounded, AdminGroup.audio,
      ready: true,
      description: 'DJ personalities, AI/template banter, song-intro '
          'generators, and the GPS-aware per-destination Banter Library '
          '(absorbed the former standalone DJ Banter Studio page as a tab).'),
  radioAutomation('Radio Automation', Icons.settings_input_antenna_rounded,
      AdminGroup.audio,
      ready: true,
      description: 'Segment library (banter/IDs/intros/promos), scheduling '
          'rules, voices, and templates — broadcast automation.',
      table: 'radio_segments'),
  radioDirector('Radio Director', Icons.radio_rounded, AdminGroup.audio,
      ready: true,
      description: 'Automatic DJ rules: priority ladder, silence engine, GPS '
          'triggers, fades, volumes, and guide defaults.'),

  species('Species', Icons.eco_rounded, AdminGroup.nature,
      ready: true,
      description: 'Create/edit species and upload photos (all categories — '
          'the one home for wildlife/plants/birds).',
      table: 'species'),
  speciesImages('Species Image Manager', Icons.photo_camera_back_rounded,
      AdminGroup.nature,
      ready: true,
      description: 'Audit which species need photos, then upload / replace / '
          'delete / approve / reorder galleries and pick the featured image, '
          'plus filename-based Image Matching as a tab — the master species '
          'image library.',
      table: 'media'),
  wildlifeAlerts('Wildlife Alerts', Icons.pets_rounded, AdminGroup.nature,
      ready: true,
      description: 'Wildlife sightings/updates for the radio.',
      table: 'wildlife_alerts'),

  mediaLibrary('Media Library', Icons.perm_media_rounded, AdminGroup.assets,
      ready: true,
      description: 'Photos, videos, audio, documents. NOTE: overlaps with '
          'Media Manager, which now covers a superset of this scope — '
          'flagged in the admin audit as a future fold-in.',
      table: 'media'),
  mediaManager('Media Manager', Icons.photo_library_rounded, AdminGroup.assets,
      ready: true,
      description: 'Dashboard, library, audit, upload center, settings, and '
          'Search & Import (Openverse/Wikimedia discovery) for all record '
          'media — absorbed the former standalone Media Search Center page '
          'as a tab.',
      table: 'media_assets'),
  downloads('Downloads', Icons.download_rounded, AdminGroup.assets,
      description: 'Offline packages per park.', table: 'downloads'),

  explorerSightings('Explorer Sightings', Icons.visibility_rounded,
      AdminGroup.platform,
      ready: true,
      description: 'Citizen-science observations from "I See Something".',
      table: 'explorer_sightings'),
  users('Users', Icons.group_rounded, AdminGroup.platform,
      description: 'Accounts and roles.', table: 'profiles'),
  subscriptions('Subscriptions', Icons.card_membership_rounded,
      AdminGroup.platform,
      description: 'Plans and subscribers.', table: 'subscriptions'),
  analytics('Analytics', Icons.insights_rounded, AdminGroup.platform,
      description: 'Popular content, downloads, revenue.'),
  databaseTools('Database Tools', Icons.storage_rounded, AdminGroup.platform,
      ready: true,
      description: 'Dashboard, table browser, maintenance, and CSV export — '
          'manage the database without the SQL editor.'),
  playbackDebug('Playback Debug', Icons.equalizer_rounded, AdminGroup.platform,
      ready: true,
      description: 'Developer tool: exercise the central PlaybackManager '
          'engine directly. Hidden from the sidebar outside debug builds — '
          'see AdminModule.visibleInGroup.'),
  settings('Settings', Icons.settings_rounded, AdminGroup.platform,
      ready: true,
      description: 'Platform configuration, AI Narration automation '
          'switches, and Voice Manager (browse/preview/assign ElevenLabs '
          'voices) as a tab.');

  const AdminModule(
    this.title,
    this.icon,
    this.group, {
    this.ready = false,
    this.description = '',
    this.table,
  });

  final String title;
  final IconData icon;
  final AdminGroup group;
  final bool ready;
  final String description;

  /// Supabase table backing this module (null for tool/overview modules).
  final String? table;

  static List<AdminModule> inGroup(AdminGroup group) =>
      AdminModule.values.where((m) => m.group == group).toList(growable: false);

  /// Same as [inGroup], but hides developer-only modules (currently just
  /// [playbackDebug]) outside debug builds. This is what the sidebar should
  /// render — [inGroup] itself is left available for anything (tests,
  /// search) that genuinely needs the full, unfiltered catalog.
  static List<AdminModule> visibleInGroup(AdminGroup group) => inGroup(group)
      .where((m) => m != AdminModule.playbackDebug || kDebugMode)
      .toList(growable: false);
}
