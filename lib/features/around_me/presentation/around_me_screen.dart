import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/around_me/presentation/widgets/experience_card.dart';
import 'package:explorer_os_mobile/features/around_me/presentation/widgets/mini_map.dart';
import 'package:explorer_os_mobile/features/around_me/providers/around_me_providers.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_enums.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_status.dart';
import 'package:explorer_os_mobile/features/gps/providers/gps_status_provider.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';

/// The primary ExplorerOS experience: "What's around me right now?".
///
/// Instead of a full park map, it shows a compact follow-map plus a live,
/// smart-sorted feed of nearby experiences that updates continuously as the
/// visitor moves — like exploring with a knowledgeable ranger.
class AroundMeScreen extends ConsumerStatefulWidget {
  const AroundMeScreen({super.key});

  @override
  ConsumerState<AroundMeScreen> createState() => _AroundMeScreenState();
}

class _AroundMeScreenState extends ConsumerState<AroundMeScreen> {
  static const _radii = [
    SearchRadius.ft250,
    SearchRadius.ft500,
    SearchRadius.mi1,
    SearchRadius.mi2,
    SearchRadius.mi5,
  ];

  @override
  void initState() {
    super.initState();
    // Ensure the Around Me coordinator is alive and try to begin live tracking
    // (best-effort; on web/without permission this simply stays idle and the
    // GPS Simulator can drive the engine instead).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(aroundMeControllerProvider);
      // Request permission and begin live tracking. Never throws; permission
      // state is reflected via gpsStatusProvider, and the GPS Simulator can
      // drive the engine when device GPS is unavailable.
      ref.read(gpsStatusProvider.notifier).requestAndStart();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snap = ref.watch(aroundMeControllerProvider);
    final gps = ref.watch(gpsStatusProvider);
    final experiences = ref.watch(aroundMeExperiencesProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 120),
          children: [
            _header(theme, snap),
            const Gap.v(AppSpacing.md),
            const MiniMap(),
            const Gap.v(AppSpacing.md),
            _radiusSelector(theme),
            const Gap.v(AppSpacing.sm),
            _statusBar(theme, snap, experiences.length),
            const Gap.v(AppSpacing.md),
            if (!snap.gpsAvailable && snap.latitude == null)
              (!gps.isGranted &&
                      gps.permission != LocationPermissionStatus.unknown)
                  ? _permissionCard(theme, gps)
                  : _waitingForGps(theme)
            else if (experiences.isEmpty)
              _empty(theme)
            else ...[
              Text('Nearby experiences',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const Gap.v(AppSpacing.sm),
              for (final e in experiences) ExperienceCard(experience: e),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(ThemeData theme, AroundMeSnapshot snap) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Around Me',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900)),
              Text(
                snap.zone != null
                    ? 'Exploring ${snap.zone}'
                    : 'What\'s around you right now',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Radio Director',
          onPressed: () => context.push(AppRoute.radioDirector.path),
          icon: const Icon(Icons.radio_rounded),
        ),
        IconButton(
          tooltip: 'GPS debug & simulator',
          onPressed: () => context.push(AppRoute.gps.path),
          icon: const Icon(Icons.travel_explore_rounded),
        ),
      ],
    );
  }

  Widget _radiusSelector(ThemeData theme) {
    final radius = ref.watch(searchRadiusProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final r in _radii) ...[
            ChoiceChip(
              label: Text(r.label),
              selected: r == radius,
              onSelected: (_) =>
                  ref.read(searchRadiusProvider.notifier).set(r),
            ),
            const Gap.h(AppSpacing.sm),
          ],
        ],
      ),
    );
  }

  Widget _statusBar(ThemeData theme, AroundMeSnapshot snap, int count) {
    final movement = switch (snap.movement) {
      MovementState.moving => 'Moving',
      MovementState.stopped => 'Stopped',
      MovementState.idle => 'Idle',
    };
    final mode = switch (snap.travelMode) {
      TravelMode.walking => 'Walking',
      TravelMode.driving => 'Driving',
      TravelMode.biking => 'Biking',
      TravelMode.stationary => 'Stationary',
    };
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(
        children: [
          Icon(
            snap.gpsAvailable
                ? Icons.gps_fixed_rounded
                : Icons.gps_off_rounded,
            size: 16,
            color: snap.gpsAvailable
                ? theme.colorScheme.primary
                : theme.colorScheme.error,
          ),
          const Gap.h(AppSpacing.sm),
          Expanded(
            child: Text(
              snap.gpsAvailable
                  ? '$movement · $mode · ${snap.speedMph.toStringAsFixed(0)} mph'
                  : 'GPS signal lost',
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Text('$count nearby', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _permissionCard(ThemeData theme, GpsStatus gps) {
    final needsSettings =
        gps.permission == LocationPermissionStatus.deniedForever ||
            gps.permission == LocationPermissionStatus.serviceDisabled;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Icon(Icons.location_disabled_rounded,
              size: 40, color: theme.colorScheme.error),
          const Gap.v(AppSpacing.md),
          Text('Location needed',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const Gap.v(AppSpacing.xs),
          Text(gps.permission.message,
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          const Gap.v(AppSpacing.md),
          FilledButton.icon(
            onPressed: () {
              if (needsSettings) {
                ref.read(gpsStatusProvider.notifier).openSettings();
              } else {
                ref.read(gpsStatusProvider.notifier).requestAndStart();
              }
            },
            icon: Icon(needsSettings
                ? Icons.settings_rounded
                : Icons.my_location_rounded),
            label: Text(needsSettings ? 'Open settings' : 'Allow location'),
          ),
          const Gap.v(AppSpacing.sm),
          TextButton(
            onPressed: () => context.push(AppRoute.gps.path),
            child: const Text('Open GPS Simulator instead'),
          ),
        ],
      ),
    );
  }

  Widget _waitingForGps(ThemeData theme) {
    return _placeholder(
      theme,
      icon: Icons.location_searching_rounded,
      title: 'Finding your location…',
      body: 'Allow location access, or open the GPS Simulator (top-right) to '
          'explore a route.',
    );
  }

  Widget _empty(ThemeData theme) {
    return _placeholder(
      theme,
      icon: Icons.explore_off_rounded,
      title: 'Nothing within range',
      body: 'No experiences within ${ref.read(searchRadiusProvider).label}. '
          'Try a larger radius or move closer to a destination.',
    );
  }

  Widget _placeholder(ThemeData theme,
      {required IconData icon, required String title, required String body}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: theme.disabledColor),
          const Gap.v(AppSpacing.md),
          Text(title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const Gap.v(AppSpacing.xs),
          Text(body,
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
