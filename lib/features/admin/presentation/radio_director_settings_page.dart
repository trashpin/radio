import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/radio_director/models/radio_director_models.dart';
import 'package:explorer_os_mobile/features/radio_director/radio_director_controller.dart';

/// Admin → Radio Director settings: tune fade/narration/trigger/priority/volume
/// behavior and the default guide personality.
class RadioDirectorSettingsPage extends ConsumerWidget {
  const RadioDirectorSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cfg = ref.watch(radioDirectorConfigProvider);
    final guide = ref.watch(radioGuideProvider);
    final cfgN = ref.read(radioDirectorConfigProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Radio Director',
          subtitle: 'Playback rules the automatic Director follows.',
        ),
        const Gap.v(AppSpacing.lg),
        AdminSectionCard(
          child: Column(
            children: [
              _num(theme, 'Fade duration (ms)', cfg.fadeDurationMs, 200, 3000, 200,
                  (v) => cfgN.set(cfg.copyWith(fadeDurationMs: v))),
              _num(theme, 'Narration delay / min quiet (s)', cfg.minQuietSeconds,
                  30, 600, 30, (v) => cfgN.set(cfg.copyWith(minQuietSeconds: v))),
              _num(
                  theme,
                  'GPS trigger distance (m)',
                  cfg.gpsTriggerDistanceMeters.round(),
                  100,
                  4000,
                  100,
                  (v) => cfgN.set(
                      cfg.copyWith(gpsTriggerDistanceMeters: v.toDouble()))),
              _num(theme, 'Interrupt threshold (priority)', cfg.interruptThreshold,
                  50, 100, 5,
                  (v) => cfgN.set(cfg.copyWith(interruptThreshold: v))),
              _pct(theme, 'Music volume', cfg.musicVolume,
                  (v) => cfgN.set(cfg.copyWith(musicVolume: v))),
              _pct(theme, 'Narration volume', cfg.narrationVolume,
                  (v) => cfgN.set(cfg.copyWith(narrationVolume: v))),
              const Divider(height: AppSpacing.xl),
              Row(children: [
                const SizedBox(width: 220, child: Text('Default guide')),
                Expanded(
                  child: DropdownButton<RadioGuidePersonality>(
                    isExpanded: true,
                    value: guide,
                    items: [
                      for (final g in RadioGuidePersonality.values)
                        DropdownMenuItem(value: g, child: Text(g.label)),
                    ],
                    onChanged: (g) =>
                        ref.read(radioGuideProvider.notifier).set(g ?? guide),
                  ),
                ),
              ]),
            ],
          ),
        ),
        const Gap.v(AppSpacing.lg),
        AdminSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Priority ladder',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const Gap.v(AppSpacing.sm),
              for (final t in RadioEventType.values)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    SizedBox(width: 220, child: Text(_label(t))),
                    Text('${cfg.priorityOverrides[t] ?? t.basePriority}',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ]),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _label(RadioEventType t) => t.name
      .replaceAllMapped(RegExp('([A-Z])'), (m) => ' ${m[1]}')
      .trim();

  Widget _num(ThemeData theme, String label, int value, int min, int max,
      int step, ValueChanged<int> on) {
    return Row(children: [
      SizedBox(width: 220, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.clamp(min, max).toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: ((max - min) ~/ step).clamp(1, 1000),
          label: '$value',
          onChanged: (v) => on(v.round()),
        ),
      ),
      SizedBox(width: 56, child: Text('$value', textAlign: TextAlign.end)),
    ]);
  }

  Widget _pct(ThemeData theme, String label, double value, ValueChanged<double> on) {
    return Row(children: [
      SizedBox(width: 220, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.clamp(0, 1),
          divisions: 20,
          label: '${(value * 100).round()}%',
          onChanged: on,
        ),
      ),
      SizedBox(
          width: 56,
          child: Text('${(value * 100).round()}%', textAlign: TextAlign.end)),
    ]);
  }
}
