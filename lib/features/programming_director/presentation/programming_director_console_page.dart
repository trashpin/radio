import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/audio_recall/audio_recall_repository.dart';
import 'package:explorer_os_mobile/features/programming_director/programming_director.dart';
import 'package:explorer_os_mobile/features/programming_director/programming_director_controller.dart';

/// A console for the Programming Director: press Play and watch the station
/// clock schedule existing assets (DJ, station IDs, intros, songs, narration,
/// wildlife, history) into a seamless rotation via the Playback Manager.
class ProgrammingDirectorConsolePage extends ConsumerWidget {
  const ProgrammingDirectorConsolePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final snap = ref.watch(programmingDirectorControllerProvider);
    final ctrl = ref.read(programmingDirectorControllerProvider.notifier);
    final inventory = ref.watch(audioInventoryProvider);
    final slots = ProgrammingClock.station.slots;
    final currentSlot = slots[snap.position % slots.length];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Programming Director'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Center(
              child: Text(snap.running ? 'ON AIR' : 'OFF',
                  style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: snap.running
                          ? theme.colorScheme.primary
                          : theme.disabledColor)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          inventory.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Inventory error: $e'),
            data: (items) => Text(
                'Scheduling ${items.where((i) => i.hasFile).length} existing '
                'audio assets across ${snap.poolCounts.length} slot pools — '
                'reusing content, never regenerating.',
                style: theme.textTheme.bodySmall),
          ),
          const Gap.v(AppSpacing.md),
          _controls(theme, snap, ctrl),
          const Gap.v(AppSpacing.lg),
          _nowPlaying(theme, snap),
          const Gap.v(AppSpacing.lg),
          _clockCard(theme, slots, currentSlot, snap),
          const Gap.v(AppSpacing.lg),
          _logCard(theme, snap),
        ],
      ),
    );
  }

  Widget _controls(ThemeData theme, ProgrammingSnapshot snap,
      ProgrammingDirectorController ctrl) {
    return Row(children: [
      FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
        onPressed: () => ctrl.togglePlay(),
        icon: Icon(snap.running ? Icons.pause_rounded : Icons.play_arrow_rounded),
        label: Text(snap.running ? 'Pause' : 'Play'),
      ),
      const Gap.h(AppSpacing.sm),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
        onPressed: snap.running ? () => ctrl.skip() : null,
        icon: const Icon(Icons.skip_next_rounded),
        label: const Text('Skip'),
      ),
    ]);
  }

  Widget _nowPlaying(ThemeData theme, ProgrammingSnapshot snap) {
    final np = snap.nowPlaying;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NOW PLAYING',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.disabledColor, letterSpacing: 1)),
          const Gap.v(AppSpacing.xs),
          Text(np?.asset?.title ?? '—',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          Text(
            np?.slotType != null
                ? '${np!.slotType!.label}'
                    '${np.reason.isNotEmpty ? '  ·  ${np.reason}' : ''}'
                : (snap.running ? 'starting…' : 'press Play'),
            style: theme.textTheme.bodySmall,
          ),
          const Gap.v(AppSpacing.sm),
          Text('Up next: ${snap.upNext ?? '—'}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _clockCard(ThemeData theme, List<ProgrammingSlotType> slots,
      ProgrammingSlotType current, ProgrammingSnapshot snap) {
    return _card(theme, 'Station clock', Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (var i = 0; i < slots.length; i++)
          _slotChip(theme, slots[i], i == (snap.position % slots.length) && snap.running,
              snap.poolCounts[slots[i]] ?? 0),
      ],
    ));
  }

  Widget _slotChip(ThemeData theme, ProgrammingSlotType slot, bool active, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.pillAll,
      ),
      child: Text('${slot.label} ($count)',
          style: theme.textTheme.labelMedium?.copyWith(
              color: active ? Colors.white : theme.colorScheme.onSurface,
              fontWeight: active ? FontWeight.w800 : FontWeight.w500)),
    );
  }

  Widget _logCard(ThemeData theme, ProgrammingSnapshot snap) {
    return _card(
      theme,
      'Programming log',
      snap.log.isEmpty
          ? Text('Press Play to start the rotation.',
              style: theme.textTheme.bodySmall)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final l in snap.log.take(20))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text(l,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12)),
                  ),
              ],
            ),
    );
  }

  Widget _card(ThemeData theme, String title, Widget child) => Container(
        width: double.infinity,
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
            const Gap.v(AppSpacing.md),
            child,
          ],
        ),
      );
}
