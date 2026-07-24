import 'package:flutter/material.dart';

/// Sidebar groupings for the admin modules.
enum AdminGroup {
  overview('Overview'),
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

  parks('Parks', Icons.forest_rounded, AdminGroup.content,
      ready: true,
      description: 'Create and manage parks/destinations.',
      table: 'destinations'),
  locations('Locations', Icons.place_rounded, AdminGroup.content,
      description: 'Points of interest within a park.', table: 'stops'),
  mapEditor('Map Editor', Icons.edit_location_alt_rounded, AdminGroup.content,
      description: 'Click-to-create locations, drag markers, trigger radius.'),
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

  explorerRadio('Explorer Radio', Icons.podcasts_rounded, AdminGroup.audio,
      description: 'Stations, programs, playlists, announcements.',
      table: 'radio_stations'),
  musicLibrary('Music Library', Icons.library_music_rounded, AdminGroup.audio,
      description: 'Songs, bulk upload, metadata, assignments.',
      table: 'songs'),
  albums('Albums', Icons.album_rounded, AdminGroup.audio,
      description: 'Album grouping and art.', table: 'albums'),

  wildlife('Wildlife', Icons.pets_rounded, AdminGroup.nature,
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
  aiContent('AI Content', Icons.auto_awesome_rounded, AdminGroup.assets,
      description: 'Generate descriptions, stories, metadata.'),
  downloads('Downloads', Icons.download_rounded, AdminGroup.assets,
      description: 'Offline packages per park.', table: 'downloads'),

  users('Users', Icons.group_rounded, AdminGroup.platform,
      description: 'Accounts and roles.', table: 'profiles'),
  subscriptions('Subscriptions', Icons.card_membership_rounded,
      AdminGroup.platform,
      description: 'Plans and subscribers.', table: 'subscriptions'),
  analytics('Analytics', Icons.insights_rounded, AdminGroup.platform,
      description: 'Popular content, downloads, revenue.'),
  settings('Settings', Icons.settings_rounded, AdminGroup.platform,
      description: 'Platform configuration.');

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
