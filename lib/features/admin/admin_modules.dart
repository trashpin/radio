import 'package:flutter/material.dart';

/// Sidebar groupings for the admin modules.
enum AdminGroup {
  overview('Overview'),
  mediaImports('Media & Imports'),
  content('Content'),
  audio('Audio'),
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
/// later. Reflects the brief's 22 modules.
enum AdminModule {
  dashboard('Dashboard', Icons.dashboard_rounded, AdminGroup.overview,
      ready: true),

  mediaImports('Media & Imports', Icons.drive_folder_upload_rounded,
      AdminGroup.mediaImports,
      ready: true,
      description: 'Upload media to storage, manage songs, import CSVs, '
          'browse files, and manage narration.'),

  destinations('Destinations', Icons.travel_explore_rounded, AdminGroup.content,
      ready: true,
      description: 'Master destination system: AI content status, filters, '
          'per-destination AI jobs, and scalable destination codes.',
      table: 'destinations'),
  parks('Parks', Icons.forest_rounded, AdminGroup.content,
      ready: true,
      description: 'Create and manage parks/destinations.',
      table: 'destinations'),
  locations('Locations', Icons.place_rounded, AdminGroup.content,
      description: 'Points of interest within a park.', table: 'stops'),
  mapEditor('Map Editor', Icons.edit_location_alt_rounded, AdminGroup.content,
      ready: true,
      description: 'Click-to-create locations, drag markers, trigger radius.',
      table: 'map_locations'),
  trails('Trails', Icons.hiking_rounded, AdminGroup.content,
      description: 'Trail name, difficulty, distance, GPX, stops.',
      table: 'trails'),
  routes('Routes', Icons.route_rounded, AdminGroup.content,
      description: 'Scenic drives and multi-stop routes.', table: 'routes'),
  stories('Stories', Icons.menu_book_rounded, AdminGroup.content,
      ready: true,
      description: 'Narrations, scripts, GPS triggers.',
      table: 'stories'),
  historicalEvents('Historical Events', Icons.history_edu_rounded,
      AdminGroup.content,
      description: 'Timeline of historical facts.', table: 'historical_events'),
  storyStudio('Story Studio', Icons.auto_stories_rounded, AdminGroup.content,
      ready: true,
      description: 'AI story production: generate, review, voice, and '
          'GPS-trigger educational stories.',
      table: 'story_library'),
  contentGenerator('Content Generator', Icons.hub_rounded, AdminGroup.content,
      ready: true,
      description: 'Master content engine: research destinations, build a '
          'knowledge base, and queue story/audio jobs at scale.',
      table: 'generation_jobs'),

  explorerRadio('Explorer Radio', Icons.podcasts_rounded, AdminGroup.audio,
      description: 'Stations, programs, playlists, announcements.',
      table: 'radio_stations'),
  musicLibrary('Music Library', Icons.library_music_rounded, AdminGroup.audio,
      ready: true,
      description: 'Upload songs (audio + artwork) straight to Supabase.',
      table: 'songs'),
  albums('Albums', Icons.album_rounded, AdminGroup.audio,
      description: 'Album grouping and art.', table: 'albums'),

  species('Species', Icons.eco_rounded, AdminGroup.nature,
      ready: true,
      description: 'Create/edit species and upload photos (all categories).',
      table: 'species'),
  wildlifeAlerts('Wildlife Alerts', Icons.pets_rounded, AdminGroup.nature,
      ready: true,
      description: 'Wildlife sightings/updates for the radio.',
      table: 'wildlife_alerts'),
  wildlife('Wildlife', Icons.cruelty_free_rounded, AdminGroup.nature,
      description: 'Species, sounds, habitat, danger level.',
      table: 'wildlife'),
  plants('Plants', Icons.local_florist_rounded, AdminGroup.nature,
      description: 'Flora guide entries.', table: 'plants'),
  birds('Birds', Icons.flutter_dash_rounded, AdminGroup.nature,
      description: 'Bird species and calls.', table: 'birds'),

  mediaLibrary('Media Library', Icons.perm_media_rounded, AdminGroup.assets,
      ready: true,
      description: 'Photos, videos, audio, documents.',
      table: 'media'),
  mediaManager('Media Manager', Icons.photo_library_rounded, AdminGroup.assets,
      ready: true,
      description: 'Dashboard, library, audit, upload center, and settings for '
          'all record media (hero, gallery, video, audio, narration, PDFs).',
      table: 'media_assets'),
  imageMatching('Image Matching', Icons.image_search_rounded, AdminGroup.assets,
      ready: true,
      description: 'Auto-match uploaded images to species by filename.',
      table: 'species'),
  narrationStudio('Narration Studio', Icons.record_voice_over_rounded,
      AdminGroup.audio,
      ready: true,
      description: 'Generate, edit, and store narration for every record.',
      table: 'narrations'),
  audioProduction('Audio Production Studio', Icons.graphic_eq_rounded,
      AdminGroup.audio,
      ready: true,
      description: 'Dashboard, production queue, voice library, audio library, '
          'batch generator, audit, and settings — narration for every record.',
      table: 'audio_assets'),
  audioRecall('Audio Recall', Icons.inventory_2_rounded, AdminGroup.audio,
      ready: true,
      description: 'One searchable inventory across every audio catalog — '
          'nothing lost, orphaned, or silently duplicated.',
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
  voiceManager('Voice Manager', Icons.graphic_eq_rounded, AdminGroup.audio,
      ready: true,
      description: 'Browse, preview, and assign ElevenLabs voices.'),
  djStudio('DJ Studio', Icons.headset_mic_rounded, AdminGroup.audio,
      ready: true,
      description: 'DJ personalities + AI/template banter and song-intro '
          'generators so stations sound like a live FM station.'),
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
  aiContent('AI Content', Icons.auto_awesome_rounded, AdminGroup.assets,
      description: 'Generate descriptions, stories, metadata.'),
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
      description: 'Exercise the central PlaybackManager engine: states, queue, '
          'priorities, ducking transitions, events, and error handling.'),
  settings('Settings', Icons.settings_rounded, AdminGroup.platform,
      ready: true,
      description: 'Platform configuration + AI Narration automation switches.');

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
}
