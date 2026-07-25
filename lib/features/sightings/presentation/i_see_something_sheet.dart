import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/sightings/models/explorer_sighting.dart';
import 'package:explorer_os_mobile/features/sightings/models/sighting_category.dart';
import 'package:explorer_os_mobile/features/sightings/providers/sighting_providers.dart';
import 'package:explorer_os_mobile/features/sightings/services/sighting_service.dart';

/// Auto-captured location context for a sighting (supplied by the caller — e.g.
/// the Radio screen knows the current station's destination). GPS/elevation are
/// best-effort; unknown values stay null.
class SightingContext {
  const SightingContext({
    this.destinationId,
    this.parkName,
    this.latitude,
    this.longitude,
    this.trail,
    this.elevationFt,
    this.travelDirection,
  });

  final String? destinationId;
  final String? parkName;
  final double? latitude;
  final double? longitude;
  final String? trail;
  final int? elevationFt;
  final String? travelDirection;
}

/// Opens the "I See Something" reporting bottom sheet.
Future<void> showISeeSomethingSheet(
  BuildContext context, {
  SightingContext location = const SightingContext(),
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => ISeeSomethingSheet(location: location),
  );
}

class ISeeSomethingSheet extends ConsumerStatefulWidget {
  const ISeeSomethingSheet({super.key, this.location = const SightingContext()});

  final SightingContext location;

  @override
  ConsumerState<ISeeSomethingSheet> createState() => _ISeeSomethingSheetState();
}

class _ISeeSomethingSheetState extends ConsumerState<ISeeSomethingSheet> {
  SightingCategory _category = SightingCategory.animal;
  final _species = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;
  SightingResult? _result; // set after save → shows confirmation view

  @override
  void dispose() {
    _species.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final loc = widget.location;
    final draft = ExplorerSighting(
      id: '',
      category: _category,
      userId: 'anonymous',
      species: _species.text.trim().isEmpty ? null : _species.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      latitude: loc.latitude,
      longitude: loc.longitude,
      elevationFt: loc.elevationFt,
      destinationId: loc.destinationId,
      parkName: loc.parkName,
      trail: loc.trail,
      travelDirection: loc.travelDirection,
    );
    final result = await ref.read(sightingServiceProvider).report(draft);
    ref.read(recentSightingsProvider.notifier).add(result.sighting);
    if (mounted) setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.sm,
        bottom: AppSpacing.lg + bottomInset,
      ),
      child: _result == null ? _form(context) : _confirmation(context),
    );
  }

  Widget _form(BuildContext context) {
    final theme = Theme.of(context);
    // Single scroll view with the action buttons INLINE at the end. Capped to
    // 88% height; content is short so Save/Cancel are visible without scrolling,
    // and the view scrolls if content ever exceeds the cap.
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.travel_explore_rounded),
                const Gap.h(AppSpacing.sm),
                Text('I See Something', style: theme.textTheme.headlineMedium),
              ],
            ),
            const Gap.v(AppSpacing.md),
            _LocationStrip(location: widget.location),
            const Gap.v(AppSpacing.lg),
            Text('Category', style: theme.textTheme.titleMedium),
            const Gap.v(AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final c in SightingCategory.values)
                  ChoiceChip(
                    avatar: Icon(c.icon,
                        size: 18,
                        color: _category == c
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.primary),
                    label: Text(c.label),
                    selected: _category == c,
                    onSelected: (_) => setState(() => _category = c),
                  ),
              ],
            ),
            const Gap.v(AppSpacing.lg),
            TextField(
              controller: _species,
              decoration: const InputDecoration(
                labelText: 'Species (search — optional)',
                hintText: 'e.g. Red-shouldered Hawk',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const Gap.v(AppSpacing.md),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes',
                alignLabelWithHint: true,
              ),
            ),
            const Gap.v(AppSpacing.md),
            OutlinedButton.icon(
              onPressed: null, // future integration
              icon: const Icon(Icons.photo_camera_rounded),
              label: const Text('Take photo (coming soon)'),
            ),
            const _RecentSightingsRow(),
            const Gap.v(AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).maybePop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const Gap.h(AppSpacing.md),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check_rounded),
                    label: Text(_saving ? 'Saving…' : 'Save sighting'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _confirmation(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result!;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            result.saved ? Icons.check_circle_rounded : Icons.cloud_off_rounded,
            size: 56,
            color: result.saved
                ? const Color(0xFF2E7D32)
                : const Color(0xFF8A6D00),
          ),
          const Gap.v(AppSpacing.md),
          Text(
            result.saved ? 'Sighting logged!' : 'Saved on device',
            style: theme.textTheme.headlineMedium,
          ),
          if (!result.saved) ...[
            const Gap.v(AppSpacing.xs),
            Text(
              'Could not reach the database yet — the observation is kept '
              'locally and shown on your map.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
          const Gap.v(AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: AppRadius.lgAll,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.smart_toy_rounded, size: 20),
                const Gap.h(AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('AI Ranger',
                          style: theme.textTheme.labelLarge),
                      const SizedBox(height: 2),
                      Text(result.reaction.text,
                          style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Gap.v(AppSpacing.lg),
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _LocationStrip extends StatelessWidget {
  const _LocationStrip({required this.location});
  final SightingContext location;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coords = (location.latitude != null && location.longitude != null)
        ? '${location.latitude!.toStringAsFixed(4)}, ${location.longitude!.toStringAsFixed(4)}'
        : 'not available';
    final now = TimeOfDay.now().format(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(
        children: [
          const Icon(Icons.my_location_rounded, size: 18),
          const Gap.h(AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(location.parkName ?? 'Current location',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                Text('$coords · $now',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Text('auto-captured', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _RecentSightingsRow extends ConsumerWidget {
  const _RecentSightingsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentSightingsProvider).value ?? const [];
    if (recent.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Gap.v(AppSpacing.md),
        Text('Recent sightings', style: theme.textTheme.titleMedium),
        const Gap.v(AppSpacing.sm),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: recent.length.clamp(0, 10),
            separatorBuilder: (_, _) => const Gap.h(AppSpacing.sm),
            itemBuilder: (context, i) {
              final s = recent[i];
              return Chip(
                avatar: Icon(s.category.icon, size: 16),
                label: Text(s.species ?? s.category.label),
              );
            },
          ),
        ),
      ],
    );
  }
}
