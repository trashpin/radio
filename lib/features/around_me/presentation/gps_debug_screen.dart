import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/around_me/logic/around_me_events.dart';
import 'package:explorer_os_mobile/features/around_me/providers/around_me_providers.dart';
import 'package:explorer_os_mobile/features/destinations/providers/destinations_provider.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_status.dart';
import 'package:explorer_os_mobile/features/gps/presentation/gps_status_card.dart';
import 'package:explorer_os_mobile/features/gps/providers/gps_providers.dart';
import 'package:explorer_os_mobile/features/gps/providers/gps_status_provider.dart';
import 'package:explorer_os_mobile/shared/models/destination.dart';

/// A developer panel that shows live GPS Intelligence state and a Simulator that
/// drives the engine with scripted fixes — walk a trail, drive a road, jump to
/// a destination, adjust speed/heading, lose/restore GPS, and enter/leave POIs —
/// generating GPS events exactly as a real device would.
class GpsDebugScreen extends ConsumerStatefulWidget {
  const GpsDebugScreen({super.key});

  @override
  ConsumerState<GpsDebugScreen> createState() => _GpsDebugScreenState();
}

class _GpsDebugScreenState extends ConsumerState<GpsDebugScreen> {
  // Ocala National Forest as a sensible default starting point.
  double _lat = 29.1872;
  double _lng = -81.7137;
  double _heading = 0; // degrees
  double _speed = 1.4; // m/s (walking)
  bool _lost = false;
  Timer? _timer;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // Tick the clock so "Current Device Time" stays live.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Make sure the coordinator/engine are alive, then seed an initial fix so
      // the debug panel + Around Me have a position to work with.
      ref.read(aroundMeControllerProvider);
      _push();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  void _push() {
    if (_lost) return;
    ref.read(gpsServiceProvider).processLocation(GPSLocation(
          latitude: _lat,
          longitude: _lng,
          timestamp: DateTime.now(),
          headingDegrees: _heading,
          speedMps: _timer == null ? 0 : _speed,
          accuracyMeters: 5,
          elevationMeters: 32,
        ));
  }

  void _tick() {
    // Advance along the current heading at the current speed (1s ticks).
    const metersPerDegLat = 111320.0;
    final dLat = _speed * math.cos(_heading * math.pi / 180) / metersPerDegLat;
    final dLng = _speed *
        math.sin(_heading * math.pi / 180) /
        (metersPerDegLat * math.cos(_lat * math.pi / 180));
    setState(() {
      _lat += dLat;
      _lng += dLng;
    });
    _push();
  }

  void _startMoving(double speed) {
    _timer?.cancel();
    setState(() {
      _speed = speed;
      _lost = false;
    });
    _push();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    setState(() {});
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    setState(() {});
    _push();
  }

  void _jumpTo(double lat, double lng) {
    _timer?.cancel();
    _timer = null;
    setState(() {
      _lat = lat;
      _lng = lng;
      _lost = false;
    });
    _push();
  }

  void _loseGps() {
    _timer?.cancel();
    _timer = null;
    setState(() => _lost = true);
    ref.read(gpsServiceProvider).reportSignalLost();
  }

  void _restoreGps() {
    setState(() => _lost = false);
    _push(); // processLocation emits GpsRecovered
  }

  void _enterNearestPoi() {
    final experiences = ref.read(aroundMeExperiencesProvider);
    if (experiences.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No nearby experiences to enter — jump nearer first.')));
      return;
    }
    final target = experiences.first;
    _jumpTo(target.latitude, target.longitude);
  }

  void _leavePoi() {
    // Jump ~400 m north to leave any POI trigger zone.
    _jumpTo(_lat + 400 / 111320.0, _lng);
  }

  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(aroundMeControllerProvider);
    final gps = ref.watch(gpsStatusProvider);
    final experiences = ref.watch(aroundMeExperiencesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('GPS Debug & Simulator'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Center(
              child: Text(_timer != null ? 'SIMULATING' : (_lost ? 'GPS LOST' : 'IDLE'),
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: _timer != null
                          ? theme.colorScheme.primary
                          : (_lost ? theme.colorScheme.error : theme.disabledColor),
                      fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const GpsStatusCard(),
          const Gap.v(AppSpacing.lg),
          _debugPanel(theme, snap, gps, experiences.length),
          const Gap.v(AppSpacing.lg),
          _deviceGps(theme, gps),
          const Gap.v(AppSpacing.lg),
          _simulator(theme),
        ],
      ),
    );
  }

  Widget _debugPanel(
      ThemeData theme, AroundMeSnapshot snap, GpsStatus gps, int expCount) {
    String f(double? v, {int digits = 5, String suffix = ''}) =>
        v == null ? '—' : '${v.toStringAsFixed(digits)}$suffix';
    String time(DateTime? t) => t == null ? '—' : t.toIso8601String().substring(11, 19);

    final rows = <(String, String)>[
      ('Latitude', f(snap.latitude, digits: 6)),
      ('Longitude', f(snap.longitude, digits: 6)),
      ('Heading', f(snap.headingDegrees, digits: 0, suffix: '°')),
      ('Speed', '${snap.speedMps.toStringAsFixed(1)} m/s · '
          '${snap.speedMph.toStringAsFixed(0)} mph'),
      ('GPS Accuracy', f(snap.accuracyMeters, digits: 0, suffix: ' m')),
      ('Altitude', f(snap.altitudeMeters, digits: 0, suffix: ' m')),
      ('Movement', snap.movement.name),
      ('Travel Mode', snap.travelMode.name),
      ('Current Destination', snap.currentDestination ?? '—'),
      ('Current Zone', snap.zone ?? '—'),
      ('Nearby Experiences', '$expCount'),
      ('Current Radius', snap.radius.label),
      ('Permission Status', gps.permission.name),
      ('GPS Enabled', _lost ? 'no (signal lost)' : '${gps.serviceEnabled}'),
      ('Last Update Time', time(gps.lastUpdate)),
      ('Updates Received', '${gps.updateCount}'),
      ('Current Device Time', time(DateTime.now())),
      ('GPS Status', _lost ? 'signal lost' : snap.status.name),
      (
        'Last Event',
        snap.lastEvent == null ? '—' : describeAroundMeEvent(snap.lastEvent!)
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: AppRadius.lgAll,
        border:
            Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Live GPS State',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const Gap.v(AppSpacing.sm),
          for (final (k, v) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(k,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.disabledColor)),
                  ),
                  Expanded(
                    child: Text(v,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _deviceGps(ThemeData theme, GpsStatus gps) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Device GPS',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const Gap.v(AppSpacing.xs),
          Text(gps.permission.message, style: theme.textTheme.bodySmall),
          const Gap.v(AppSpacing.sm),
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
            _btn('Request permission & start', Icons.my_location_rounded,
                () => ref.read(gpsStatusProvider.notifier).requestAndStart()),
            _btn('Re-check permission', Icons.refresh_rounded,
                () => ref.read(gpsStatusProvider.notifier).refreshPermission()),
            if (!gps.isGranted &&
                gps.permission != LocationPermissionStatus.unknown)
              _btn('Open settings', Icons.settings_rounded,
                  () => ref.read(gpsStatusProvider.notifier).openSettings()),
          ]),
        ],
      ),
    );
  }

  Widget _simulator(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Simulator',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const Gap.v(AppSpacing.sm),
          _destinationJump(theme),
          const Gap.v(AppSpacing.md),
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
            _btn('Walk trail', Icons.directions_walk_rounded,
                () => _startMoving(1.4)),
            _btn('Drive road', Icons.directions_car_rounded,
                () => _startMoving(13.4)),
            _btn('Stop', Icons.stop_rounded, _stop),
            _btn('Enter nearest POI', Icons.login_rounded, _enterNearestPoi),
            _btn('Leave POI', Icons.logout_rounded, _leavePoi),
            _lost
                ? _btn('Restore GPS', Icons.gps_fixed_rounded, _restoreGps)
                : _btn('Lose GPS', Icons.gps_off_rounded, _loseGps),
          ]),
          const Gap.v(AppSpacing.md),
          _slider(
            theme,
            'Heading',
            '${_heading.round()}°',
            _heading,
            0,
            359,
            (v) {
              setState(() => _heading = v);
              if (_timer == null) _push();
            },
          ),
          _slider(
            theme,
            'Speed',
            '${(_speed * 2.2369).toStringAsFixed(0)} mph',
            _speed,
            0,
            30,
            (v) {
              setState(() => _speed = v);
              if (_timer != null) {
                _startMoving(v); // restart timer with new speed
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _destinationJump(ThemeData theme) {
    final destinations =
        ref.watch(destinationsProvider).asData?.value ?? const <Destination>[];
    final withCoords = destinations
        .where((d) => d.latitude != null && d.longitude != null)
        .toList(growable: false);
    if (withCoords.isEmpty) {
      return Text('No destinations with coordinates to jump to.',
          style: theme.textTheme.bodySmall);
    }
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<Destination>(
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Jump to destination',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              for (final d in withCoords)
                DropdownMenuItem(value: d, child: Text(d.name)),
            ],
            onChanged: (d) {
              if (d != null) _jumpTo(d.latitude!, d.longitude!);
            },
          ),
        ),
      ],
    );
  }

  Widget _slider(ThemeData theme, String label, String value, double v,
      double min, double max, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 70, child: Text(label, style: theme.textTheme.bodySmall)),
        Expanded(
          child: Slider(value: v.clamp(min, max), min: min, max: max, onChanged: onChanged),
        ),
        SizedBox(
            width: 56,
            child: Text(value,
                textAlign: TextAlign.end, style: theme.textTheme.bodySmall)),
      ],
    );
  }

  Widget _btn(String label, IconData icon, VoidCallback onTap) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}
