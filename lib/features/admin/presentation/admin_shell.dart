import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/admin_modules.dart';
import 'package:explorer_os_mobile/features/admin/admin_state.dart';
import 'package:explorer_os_mobile/features/admin/presentation/content_generator_page.dart';
import 'package:explorer_os_mobile/features/admin/presentation/content_pages.dart';
import 'package:explorer_os_mobile/features/admin/presentation/content_uploader_page.dart';
import 'package:explorer_os_mobile/features/admin/presentation/dashboard_page.dart';
import 'package:explorer_os_mobile/features/admin/presentation/admin_settings_page.dart';
import 'package:explorer_os_mobile/features/admin/presentation/database_tools_page.dart';
import 'package:explorer_os_mobile/features/admin/presentation/destination_dashboard_page.dart';
import 'package:explorer_os_mobile/features/admin/presentation/dj_studio_page.dart';
import 'package:explorer_os_mobile/features/admin/presentation/image_matching_page.dart';
import 'package:explorer_os_mobile/features/admin/presentation/map_editor_page.dart';
import 'package:explorer_os_mobile/features/admin/audio_studio/presentation/audio_production_page.dart';
import 'package:explorer_os_mobile/features/admin/media_manager/presentation/media_manager_page.dart';
import 'package:explorer_os_mobile/features/admin/presentation/media_imports_page.dart';
import 'package:explorer_os_mobile/features/admin/presentation/narration_studio_page.dart';
import 'package:explorer_os_mobile/features/admin/presentation/playback_debug_page.dart';
import 'package:explorer_os_mobile/features/admin/presentation/radio_automation_page.dart';
import 'package:explorer_os_mobile/features/admin/presentation/radio_director_settings_page.dart';
import 'package:explorer_os_mobile/features/admin/presentation/song_uploader_page.dart';
import 'package:explorer_os_mobile/features/admin/presentation/story_studio_page.dart';
import 'package:explorer_os_mobile/features/admin/presentation/species_admin_page.dart';
import 'package:explorer_os_mobile/features/admin/presentation/voice_manager_page.dart';
import 'package:explorer_os_mobile/features/admin/presentation/sightings_page.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';

/// The admin control center: responsive layout with a left sidebar, a top bar
/// (global search, notifications, quick actions, theme toggle, profile), a
/// breadcrumb, and a content pane that swaps with the selected module.
class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({super.key});

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _searchController = TextEditingController();

  static const double _breakpoint = 1000;
  static const double _sidebarWidth = 264;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _pageFor(AdminModule module) {
    switch (module) {
      case AdminModule.dashboard:
        return const DashboardPage();
      case AdminModule.mediaImports:
        return const MediaImportsPage();
      case AdminModule.destinations:
        return const DestinationDashboardPage();
      case AdminModule.settings:
        return const AdminSettingsPage();
      case AdminModule.parks:
        return const ParksPage();
      case AdminModule.mediaLibrary:
        return const MediaLibraryPage();
      case AdminModule.stories:
        return const ContentUploaderPage(storiesConfig);
      case AdminModule.wildlifeAlerts:
        return const ContentUploaderPage(wildlifeConfig);
      case AdminModule.safetyMessages:
        return const ContentUploaderPage(safetyConfig);
      case AdminModule.programmingSchedule:
        return const ContentUploaderPage(scheduleConfig);
      case AdminModule.explorerSightings:
        return const SightingsAdminPage();
      case AdminModule.imageMatching:
        return const ImageMatchingPage();
      case AdminModule.narrationStudio:
        return const NarrationStudioPage();
      case AdminModule.voiceManager:
        return const VoiceManagerPage();
      case AdminModule.djStudio:
        return const DjStudioPage();
      case AdminModule.radioAutomation:
        return const RadioAutomationPage();
      case AdminModule.radioDirector:
        return const RadioDirectorSettingsPage();
      case AdminModule.storyStudio:
        return const StoryStudioPage();
      case AdminModule.contentGenerator:
        return const ContentGeneratorPage();
      case AdminModule.databaseTools:
        return const DatabaseToolsPage();
      case AdminModule.playbackDebug:
        return const PlaybackDebugPage();
      case AdminModule.mapEditor:
        return const MapEditorPage();
      case AdminModule.species:
        return const SpeciesAdminPage();
      case AdminModule.musicLibrary:
        return const SongUploaderPage();
      case AdminModule.mediaManager:
        return const MediaManagerPage();
      case AdminModule.audioProduction:
        return const AudioProductionPage();
      default:
        return ModulePlaceholder(module: module);
    }
  }

  @override
  Widget build(BuildContext context) {
    final module = ref.watch(adminSelectedModuleProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _breakpoint;
        final content = Column(
          children: [
            _TopBar(
              wide: wide,
              controller: _searchController,
              onMenu: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            _Breadcrumb(module: module),
            Expanded(
              child: KeyedSubtree(
                key: ValueKey(module),
                child: _pageFor(module),
              ),
            ),
          ],
        );

        if (wide) {
          return Scaffold(
            key: _scaffoldKey,
            body: Row(
              children: [
                const SizedBox(width: _sidebarWidth, child: _Sidebar()),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            ),
          );
        }

        return Scaffold(
          key: _scaffoldKey,
          drawer: const Drawer(child: _Sidebar()),
          body: content,
        );
      },
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selected = ref.watch(adminSelectedModuleProvider);

    return Container(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: AppRadius.smAll,
                    ),
                    child: const Icon(Icons.filter_hdr_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const Gap.h(AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ExplorerOS',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        Text('Admin',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                children: [
                  for (final group in AdminGroup.values) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 4),
                      child: Text(
                        group.label.toUpperCase(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w700,
                          color: theme.disabledColor,
                        ),
                      ),
                    ),
                    for (final module in AdminModule.inGroup(group))
                      _SidebarItem(
                        module: module,
                        selected: module == selected,
                        onTap: () {
                          ref
                              .read(adminSelectedModuleProvider.notifier)
                              .select(module);
                          final scaffold = Scaffold.maybeOf(context);
                          if (scaffold?.hasDrawer ?? false) {
                            Navigator.of(context).maybePop();
                          }
                        },
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.module,
    required this.selected,
    required this.onTap,
  });

  final AdminModule module;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        selected ? theme.colorScheme.primary : theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: 1),
      child: Material(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: AppRadius.mdAll,
        child: InkWell(
          borderRadius: AppRadius.mdAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: 11),
            child: Row(
              children: [
                Icon(module.icon, size: 20, color: color),
                const Gap.h(AppSpacing.md),
                Expanded(
                  child: Text(
                    module.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: color,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (!module.ready)
                  Icon(Icons.circle,
                      size: 6, color: theme.disabledColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.wide,
    required this.controller,
    required this.onMenu,
  });

  final bool wide;
  final TextEditingController controller;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
              child: Row(
                children: [
                  if (!wide)
                    IconButton(
                        onPressed: onMenu,
                        icon: const Icon(Icons.menu_rounded)),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: TextField(
                        controller: controller,
                        onChanged: (v) =>
                            ref.read(adminSearchProvider.notifier).set(v),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Search parks, media, stories…',
                          prefixIcon: const Icon(Icons.search_rounded, size: 20),
                          filled: true,
                          fillColor:
                              theme.colorScheme.onSurface.withValues(alpha: 0.05),
                          border: OutlineInputBorder(
                            borderRadius: AppRadius.pillAll,
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md, vertical: 0),
                        ),
                      ),
                    ),
                  ),
                  const Gap.h(AppSpacing.sm),
                  if (wide) ...[
                    const Base44Badge(),
                    const Gap.h(AppSpacing.sm),
                  ],
                  _QuickActions(),
                  IconButton(
                    tooltip: 'Notifications',
                    onPressed: () {},
                    icon: Badge(
                      smallSize: 8,
                      child: const Icon(Icons.notifications_none_rounded),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Toggle theme',
                    onPressed: () =>
                        ref.read(adminThemeModeProvider.notifier).toggle(),
                    icon: Icon(isDark
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded),
                  ),
                  const Gap.h(AppSpacing.sm),
                  const _ProfileMenu(),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

class _QuickActions extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<AdminModule>(
      tooltip: 'Quick navigate',
      icon: const Icon(Icons.bolt_rounded),
      onSelected: (m) =>
          ref.read(adminSelectedModuleProvider.notifier).select(m),
      itemBuilder: (context) => const [
        PopupMenuItem(value: AdminModule.parks, child: Text('Go to Parks')),
        PopupMenuItem(
            value: AdminModule.mediaLibrary, child: Text('Go to Media')),
        PopupMenuItem(value: AdminModule.stories, child: Text('Go to Stories')),
      ],
    );
  }
}

class _ProfileMenu extends StatelessWidget {
  const _ProfileMenu();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Account',
      onSelected: (v) async {
        if (v == 'signout' && SupabaseService.isConfigured) {
          await Supabase.instance.client.auth.signOut();
        }
      },
      child: CircleAvatar(
        radius: 16,
        backgroundColor: theme.colorScheme.primary,
        child: const Text('EX',
            style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
      ),
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'profile', child: Text('Profile')),
        PopupMenuItem(value: 'settings', child: Text('Settings')),
        PopupMenuItem(value: 'signout', child: Text('Sign out')),
      ],
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.module});

  final AdminModule module;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: theme.disabledColor);
    return Container(
      width: double.infinity,
      color: theme.scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl, AppSpacing.sm, AppSpacing.xl, 0),
      child: Row(
        children: [
          Icon(Icons.home_rounded, size: 14, color: theme.disabledColor),
          Text('  ${module.group.label}  /  ', style: muted),
          Text(module.title,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
