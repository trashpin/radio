import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/presentation/voice_manager_page.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/narration/data/narration_settings_repository.dart';
import 'package:explorer_os_mobile/features/narration/voices.dart';

/// Admin Settings — General (AI Narration automation switches) + Voices
/// (browse/preview/assign ElevenLabs voices — absorbed the former standalone
/// Voice Manager page as a tab). Everything in General defaults OFF: scripts,
/// audio, and publishing are all manual unless enabled.
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
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: const TabBar(
              tabs: [
                Tab(text: 'General'),
                Tab(text: 'Voices'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _GeneralTab(onSet: (col, v) => _set(context, ref, col, v)),
                const VoiceManagerPage(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GeneralTab extends ConsumerWidget {
  const _GeneralTab({required this.onSet});
  final void Function(String column, bool value) onSet;

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
                onChanged: (v) => onSet('auto_generate_scripts', v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto-generate audio after approval'),
                subtitle: const Text(
                    'When a script is approved, send it to ElevenLabs.'),
                value: s.autoGenerateAudio,
                onChanged: (v) => onSet('auto_generate_audio', v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto-publish after audio'),
                subtitle: const Text(
                    'When audio is generated, publish to Explorer Radio.'),
                value: s.autoPublish,
                onChanged: (v) => onSet('auto_publish', v),
              ),
              const Divider(),
              const Gap.v(AppSpacing.sm),
              Row(
                children: [
                  const Expanded(
                    child: Text('Global default voice',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  DropdownButton<String>(
                    value: narrationVoices.any((v) => v.id == s.defaultVoiceId)
                        ? s.defaultVoiceId
                        : null,
                    hint: const Text('Select voice', style: TextStyle(fontSize: 13)),
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final v in narrationVoices)
                        DropdownMenuItem(
                            value: v.id,
                            child: Text(v.name, style: const TextStyle(fontSize: 13))),
                    ],
                    onChanged: (voiceId) async {
                      if (voiceId == null) return;
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await ref
                            .read(narrationSettingsRepositoryProvider)
                            .setDefaultVoice(voiceId, voiceNameForId(voiceId) ?? voiceId);
                        ref.read(narrationSettingsRefreshProvider.notifier).bump();
                      } catch (e) {
                        messenger.showSnackBar(SnackBar(
                            content: Text('Could not save (run migration 0024): $e')));
                      }
                    },
                  ),
                ],
              ),
              Text(
                'Used when a narration (and its destination) has no voice set.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
