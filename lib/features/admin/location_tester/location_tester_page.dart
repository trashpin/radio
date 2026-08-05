import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/location_engine.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

const double _mile = 1609.344;

/// Admin → Location Tester. Answers "what shows up at coordinate X?" against the
/// LIVE Location Engine — the exact same query the user's Radio/Nearby/GPS use —
/// without needing a device or the driving simulator.
///
/// For every master location it shows the great-circle distance from the entered
/// point and whether the engine returns it, and if not, the precise reason
/// (inactive/hidden, no coordinates, draft/archived, or out of range). This is
/// the admin-side twin of the on-device GPS Debug diagnostic.
class LocationTesterPage extends ConsumerStatefulWidget {
  const LocationTesterPage({super.key});

  @override
  ConsumerState<LocationTesterPage> createState() => _LocationTesterPageState();
}

class _LocationTesterPageState extends ConsumerState<LocationTesterPage> {
  final _lat = TextEditingController(text: '29.187199');
  final _lng = TextEditingController(text: '-82.140092');
  double _radiusMiles = 20;
  ({double lat, double lng, double miles})? _query;

  @override
  void dispose() {
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  void _run() {
    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter a valid latitude and longitude.')));
      return;
    }
    setState(() => _query = (lat: lat, lng: lng, miles: _radiusMiles));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(masterLocationsProvider);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const AdminPageHeader(
          title: 'Location Tester',
          subtitle:
              'Enter a GPS coordinate and radius to see exactly what the user '
              'gets there — every location, its distance, and why it is kept '
              'or rejected by the Location Engine.',
        ),
        const Gap.v(AppSpacing.md),
        _inputCard(theme),
        const Gap.v(AppSpacing.lg),
        async.when(
          loading: () => const Center(child: Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: CircularProgressIndicator(),
          )),
          error: (e, _) => Text('Failed to load locations: $e'),
          data: (all) => _results(theme, all),
        ),
      ],
    );
  }

  Widget _inputCard(ThemeData theme) => Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: AppRadius.lgAll,
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: _field(_lat, 'Latitude')),
              const Gap.h(AppSpacing.sm),
              Expanded(child: _field(_lng, 'Longitude')),
            ]),
            const Gap.v(AppSpacing.sm),
            Row(children: [
              const Text('Radius: '),
              Expanded(
                child: Slider(
                  value: _radiusMiles,
                  min: 1,
                  max: 50,
                  divisions: 49,
                  label: '${_radiusMiles.round()} mi',
                  onChanged: (v) => setState(() => _radiusMiles = v),
                ),
              ),
              SizedBox(
                  width: 48, child: Text('${_radiusMiles.round()} mi')),
              const Gap.h(AppSpacing.sm),
              FilledButton.icon(
                onPressed: _run,
                icon: const Icon(Icons.travel_explore_rounded, size: 18),
                label: const Text('Run test'),
              ),
            ]),
          ],
        ),
      );

  Widget _field(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType:
            const TextInputType.numberWithOptions(signed: true, decimal: true),
        decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder()),
      );

  Widget _results(ThemeData theme, List<MasterLocation> all) {
    final q = _query;
    if (q == null) {
      return Text('Enter a coordinate and tap "Run test".',
          style: theme.textTheme.bodySmall);
    }
    // The exact engine the user hits (requireAudio=false, no type/exclude).
    final returned = const LocationEngine()
        .nearby(q.lat, q.lng, all, maxMiles: q.miles);
    final returnedIds = {for (final r in returned) r.location.id};

    // Classify EVERY location by distance + the reason the engine would give,
    // so a "why isn't X here?" question is answerable at a glance.
    final rows = <_Row>[];
    for (final l in all) {
      final hasCoords = l.hasCoordinates;
      final m = hasCoords
          ? GeoMath.distanceMeters(q.lat, q.lng, l.latitude!, l.longitude!)
          : double.infinity;
      String? reason;
      if (!l.active || l.hidden || !hasCoords) {
        reason = !hasCoords
            ? 'no coordinates'
            : (!l.active ? 'inactive' : 'hidden');
      } else if (l.isPublishBlocked) {
        reason = 'draft/archived (unpublished)';
      } else if (!returnedIds.contains(l.id)) {
        reason = 'out of range (> ${q.miles.round()} mi)';
      }
      rows.add(_Row(l, m, reason == null, reason));
    }
    rows.sort((a, b) => a.meters.compareTo(b.meters));

    final kept = rows.where((r) => r.kept).toList();
    final nearest = kept.isEmpty ? null : kept.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.06),
            borderRadius: AppRadius.lgAll,
            border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('(${q.lat}, ${q.lng}) · radius ${q.miles.round()} mi',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const Gap.v(AppSpacing.xs),
            Text(
              '${all.length} locations in database · '
              '${kept.length} returned to the user'
              '${nearest == null ? '' : ' · nearest: "${nearest.loc.name}" '
                  '${(nearest.meters / _mile).toStringAsFixed(2)} mi'}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (kept.isEmpty) ...[
              const Gap.v(AppSpacing.xs),
              Text(
                'Nothing would show here. Check the rejected list below for the '
                'reason (e.g. everything out of range, unpublished, or no GPS).',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
          ]),
        ),
        const Gap.v(AppSpacing.lg),
        _section(theme, 'Returned to user (${kept.length})',
            kept.take(60).toList(), returned: true),
        const Gap.v(AppSpacing.lg),
        _section(
            theme,
            'Rejected (nearest 25)',
            rows.where((r) => !r.kept).take(25).toList(),
            returned: false),
      ],
    );
  }

  Widget _section(ThemeData theme, String title, List<_Row> rows,
      {required bool returned}) {
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
          Text(title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const Gap.v(AppSpacing.sm),
          if (rows.isEmpty)
            Text(returned ? 'None.' : 'None — everything nearby is returned.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.disabledColor)),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 66,
                    child: Text(
                      r.meters.isFinite
                          ? '${(r.meters / _mile).toStringAsFixed(2)} mi'
                          : '—',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    child: Text('${r.loc.name}  ·  ${r.loc.type.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium),
                  ),
                  if (returned)
                    Icon(Icons.check_circle_rounded,
                        size: 18, color: theme.colorScheme.primary)
                  else
                    Flexible(
                      child: Text(r.reason ?? '',
                          textAlign: TextAlign.end,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.error)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Row {
  const _Row(this.loc, this.meters, this.kept, this.reason);
  final MasterLocation loc;
  final double meters;
  final bool kept;
  final String? reason;
}
