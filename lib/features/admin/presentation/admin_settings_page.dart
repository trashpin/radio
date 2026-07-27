import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/narration/data/narration_settings_repository.dart';

/// Admin Settings — currently the AI Narration automation switches. Everything
/// defaults OFF: scripts, audio, and publishing are all manual unless enabled.
class AdminSettingsPage extends ConsumerWidget {
  const AdminSettingsPage({super.key});

  Future<void> _set(BuildContext context, WidgetRef ref, String column,
      bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(narrationSettingsRepositoryProvider).setFlag(column, value);
      ref.read(narrationSettingsRefreshProvider.notifier).bump();
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Could not save (run migration 0023): $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(narrationSettingsProvider);
    final s = async.value ?? const NarrationSettings();
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Settings',
          subtitle: 'Platform configuration.',
        ),
        const Gap.v(AppSpacing.lg),
        AdminSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('AI Narration',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Gap.v(AppSpacing.xs),
              Text(
                'Automation is OFF by default so no AI/ElevenLabs cost is ever '
                'incurred without an explicit action. Turn a switch on only if '
                'you want that stage to run automatically.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Gap.v(AppSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto-generate scripts after import'),
                subtitle: const Text(
                    'When a destination is imported, generate its scripts.'),
                value: s.autoGenerateScripts,
                onChanged: (v) => _set(context, ref, 'auto_generate_scripts', v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto-generate audio after approval'),
                subtitle: const Text(
                    'When a script is approved, send it to ElevenLabs.'),
                value: s.autoGenerateAudio,
                onChanged: (v) => _set(context, ref, 'auto_generate_audio', v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto-publish after audio'),
                subtitle: const Text(
                    'When audio is generated, publish to Explorer Radio.'),
                value: s.autoPublish,
                onChanged: (v) => _set(context, ref, 'auto_publish', v),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
