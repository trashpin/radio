import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/gps/gps_connection.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_status.dart';
import 'package:explorer_os_mobile/features/gps/providers/gps_status_provider.dart';
import 'package:explorer_os_mobile/features/location_intelligence/data/location_content_repository.dart';

/// A polished, self-contained GPS status card — the user never wonders whether
/// GPS is working. Shows the connection phase, progress steps, health/accuracy,
/// county + coordinates, and the right recovery buttons (grant / enable / open
/// settings). Kicks off location acquisition on mount.
class GpsStatusCard extends ConsumerStatefulWidget {
  const GpsStatusCard({super.key, this.onContinueWithout, this.compact = false});

  /// Optional "Continue without GPS" affordance (e.g. on a gating screen).
  final VoidCallback? onContinueWithout;
  final bool compact;

  @override
  ConsumerState<GpsStatusCard> createState() => _GpsStatusCardState();
}

class _P {
  static const card = Color(0xFF17211B);
  static const green = Color(0xFF33B074);
  static const gold = Color(0xFFF2B33D);
  static const red = Color(0xFFE5734B);
  static const text = Color(0xFFF3F6F2);
  static const dim = Color(0xFF9CA8A1);
}

class _GpsStatusCardState extends ConsumerState<GpsStatusCard> {
  Timer? _tick;
  int _searchingSeconds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gpsStatusProvider.notifier).requestAndStart().catchError(
          (_) => ref.read(gpsStatusProvider));
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final s = ref.read(gpsStatusProvider);
      setState(() => _searchingSeconds = s.hasFix ? 0 : _searchingSeconds + 1);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Color _healthColor(GpsHealth h) => switch (h) {
        GpsHealth.excellent || GpsHealth.good => _P.green,
        GpsHealth.fair => _P.gold,
        GpsHealth.poor => _P.red,
        GpsHealth.none => _P.dim,
      };

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(gpsStatusProvider);
    final county = ref.watch(locationContextProvider).county;
    final conn = deriveGpsConnection(status,
        county: county, searchingSeconds: _searchingSeconds);
    final ctrl = ref.read(gpsStatusProvider.notifier);
    final healthColor = _healthColor(conn.health);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: _P.card, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _statusDot(conn),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_title(conn),
                  style: const TextStyle(
                      color: _P.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
            ),
            if (conn.health != GpsHealth.none)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: healthColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(conn.health.label,
                    style: TextStyle(
                        color: healthColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
          ]),
          const SizedBox(height: 8),
          Text(conn.message,
              style: const TextStyle(color: _P.dim, fontSize: 13, height: 1.35)),
          if (!widget.compact) ...[
            const SizedBox(height: 14),
            for (final step in conn.steps) _stepRow(step),
            if (status.hasFix) ...[
              const SizedBox(height: 12),
              _liveStats(status, county, conn),
            ],
          ],
          const SizedBox(height: 14),
          _actions(conn, ctrl),
        ],
      ),
    );
  }

  Widget _statusDot(GpsConnectionState conn) {
    final ready = conn.phase == GpsPhase.ready;
    final color = ready
        ? _P.green
        : conn.needsAction
            ? _P.red
            : _P.gold;
    return Container(
      width: 12, height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  String _title(GpsConnectionState conn) => switch (conn.phase) {
        GpsPhase.ready => 'GPS Connected',
        GpsPhase.resolvingCounty => 'Getting your county…',
        GpsPhase.searching => 'Finding your location…',
        GpsPhase.checkingPermission => 'Connecting to GPS…',
        GpsPhase.gpsDisabled => 'GPS is turned off',
        GpsPhase.permissionDenied => 'Location permission needed',
        GpsPhase.permissionBlocked => 'Location blocked',
      };

  Widget _stepRow(GpsStep step) {
    final (icon, color) = switch (step.state) {
      GpsStepState.done => (Icons.check_circle_rounded, _P.green),
      GpsStepState.active => (Icons.radio_button_checked_rounded, _P.gold),
      GpsStepState.pending => (Icons.radio_button_unchecked_rounded, _P.dim),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Text(step.label,
            style: TextStyle(
                color: step.state == GpsStepState.pending ? _P.dim : _P.text,
                fontSize: 13)),
      ]),
    );
  }

  Widget _liveStats(GpsStatus status, String? county, GpsConnectionState conn) {
    String ago() {
      final t = status.lastUpdate;
      if (t == null) return '—';
      final s = DateTime.now().difference(t).inSeconds;
      return s <= 1 ? 'just now' : '$s seconds ago';
    }

    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            SizedBox(
                width: 110,
                child: Text(k,
                    style: const TextStyle(color: _P.dim, fontSize: 12))),
            Expanded(
                child: Text(v,
                    style: const TextStyle(color: _P.text, fontSize: 12))),
          ]),
        );

    return Column(children: [
      row('Accuracy', accuracyLabel(status.accuracyMeters)),
      if ((county ?? '').isNotEmpty) row('County', '$county County'),
      row('Coordinates',
          '${status.latitude?.toStringAsFixed(4)}, ${status.longitude?.toStringAsFixed(4)}'),
      row('Last update', ago()),
    ]);
  }

  Widget _actions(GpsConnectionState conn, GpsStatusController ctrl) {
    final buttons = <Widget>[];
    switch (conn.phase) {
      case GpsPhase.permissionDenied:
        buttons.add(_primary('Grant Permission', () => ctrl.requestAndStart()));
      case GpsPhase.permissionBlocked:
      case GpsPhase.gpsDisabled:
        buttons.add(_primary('Open Settings', () async {
          await ctrl.openSettings();
          await ctrl.refreshPermission();
        }));
      case GpsPhase.searching:
        if (conn.timedOut) {
          buttons.add(_secondary('Retry', () => ctrl.requestAndStart()));
        }
      case GpsPhase.checkingPermission:
      case GpsPhase.resolvingCounty:
      case GpsPhase.ready:
        break;
    }
    if (widget.onContinueWithout != null && conn.phase != GpsPhase.ready) {
      buttons.add(_secondary('Continue Without GPS', widget.onContinueWithout!));
    }
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 10, runSpacing: 8, children: buttons);
  }

  Widget _primary(String label, VoidCallback onTap) => FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
            backgroundColor: _P.green,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        child: Text(label),
      );

  Widget _secondary(String label, VoidCallback onTap) => OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
            foregroundColor: _P.text,
            side: const BorderSide(color: _P.dim),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        child: Text(label),
      );
}
