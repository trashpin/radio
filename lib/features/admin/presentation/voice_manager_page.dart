import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/narration/data/voice_assignment_repository.dart';
import 'package:explorer_os_mobile/features/narration/data/voice_repository.dart';
import 'package:explorer_os_mobile/features/narration/models/narration_category.dart';
import 'package:explorer_os_mobile/features/narration/models/voice.dart';

/// Admin → Voice Manager: browse ElevenLabs voices, preview them, rename them,
/// pick the default voice, and assign a default voice per content category
/// (persisted to `voice_assignments`). Audio generation uses the assigned voice
/// automatically — no manual voice-ID entry.
class VoiceManagerPage extends ConsumerStatefulWidget {
  const VoiceManagerPage({super.key});

  @override
  ConsumerState<VoiceManagerPage> createState() => _VoiceManagerPageState();
}

class _VoiceManagerPageState extends ConsumerState<VoiceManagerPage> {
  final AudioPlayer _player = AudioPlayer();
  String? _previewing;
  final Map<String, String> _assignments = {}; // category token -> voice_id
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    _player.playerStateStream.listen((st) {
      if (st.processingState == ProcessingState.completed && mounted) {
        setState(() => _previewing = null);
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _preview(Voice v) async {
    if (_previewing == v.voiceId) {
      await _player.stop();
      setState(() => _previewing = null);
      return;
    }
    if (v.previewUrl == null) return;
    setState(() => _previewing = v.voiceId);
    try {
      await _player.setUrl(v.previewUrl!);
      await _player.play();
    } catch (e) {
      if (mounted) {
        setState(() => _previewing = null);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Preview failed: $e')));
      }
    }
  }

  void _assign(String category, Voice v) {
    setState(() => _assignments[category] = v.voiceId);
    final label =
        ref.read(voiceLabelsProvider.notifier).labelFor(v.voiceId, v.name);
    // Persist (best-effort — needs migration 0008).
    ref
        .read(voiceAssignmentRepositoryProvider)
        .assign(category, label, v.voiceId)
        .catchError((_) {});
  }

  Future<void> _editLabel(Voice v) async {
    final current =
        ref.read(voiceLabelsProvider.notifier).labelFor(v.voiceId, v.name);
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit label — ${v.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Display label', hintText: 'e.g. Ranger Sarah'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      ref.read(voiceLabelsProvider.notifier).setLabel(v.voiceId, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(voicesProvider);
    final selected = ref.watch(selectedVoiceProvider);
    ref.watch(voiceLabelsProvider); // rebuild on label changes
    final labels = ref.read(voiceLabelsProvider.notifier);

    // Seed the assignment table from persisted assignments (once).
    final loaded = ref.watch(voiceAssignmentsProvider).value;
    if (!_seeded && loaded != null) {
      _seeded = true;
      for (final e in loaded.entries) {
        if (e.value.defaultVoiceId != null) {
          _assignments[e.key] = e.value.defaultVoiceId!;
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AdminPageHeader(
          title: 'Voice Manager',
          subtitle: 'ElevenLabs voices — preview, rename, and assign a default '
              'voice per content category',
          actions: [
            FilledButton.icon(
              onPressed: () => refreshVoices(ref),
              style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg)),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh Voices'),
            ),
          ],
        ),
        const Gap.v(AppSpacing.lg),
        if (selected != null)
          AdminSectionCard(
            child: Row(children: [
              const Icon(Icons.record_voice_over_rounded, color: Colors.teal),
              const Gap.h(AppSpacing.md),
              Expanded(
                child: Text(
                    'Default voice: ${labels.labelFor(selected.voiceId, selected.name)}',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        const Gap.v(AppSpacing.lg),
        async.when(
          loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator())),
          error: (e, _) => AdminSectionCard(
              child: AdminEmptyState(
                  icon: Icons.error_outline_rounded,
                  message: 'Could not load voices.\n$e')),
          data: (voices) => Column(children: [
            LayoutBuilder(builder: (context, c) {
              final cols = (c.maxWidth / 320).floor().clamp(1, 4);
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpacing.md,
                crossAxisSpacing: AppSpacing.md,
                childAspectRatio: 1.2,
                children: [
                  for (final v in voices)
                    _VoiceCard(
                      voice: v,
                      label: labels.labelFor(v.voiceId, v.name),
                      selected: selected?.voiceId == v.voiceId,
                      playing: _previewing == v.voiceId,
                      onPreview: () => _preview(v),
                      onSelectDefault: () =>
                          ref.read(selectedVoiceProvider.notifier).select(v),
                      onEditLabel: () => _editLabel(v),
                    ),
                ],
              );
            }),
            const Gap.v(AppSpacing.lg),
            _assignmentTable(voices, labels),
          ]),
        ),
      ],
    );
  }

  Widget _assignmentTable(List<Voice> voices, VoiceLabels labels) {
    final theme = Theme.of(context);
    return AdminSectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Voice assignment by content type',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        Text('Generate Audio uses these automatically.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
        const Gap.v(AppSpacing.md),
        for (final cat in narrationCategories)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(
                  width: 180,
                  child: Text(cat.label,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600))),
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _assignments[cat.token],
                  hint: const Text('— choose default voice —'),
                  onChanged: (id) {
                    if (id == null) return;
                    _assign(cat.token,
                        voices.firstWhere((v) => v.voiceId == id));
                  },
                  items: [
                    for (final v in voices)
                      DropdownMenuItem(
                        value: v.voiceId,
                        child: Text(labels.labelFor(v.voiceId, v.name)),
                      ),
                  ],
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _VoiceCard extends StatelessWidget {
  const _VoiceCard({
    required this.voice,
    required this.label,
    required this.selected,
    required this.playing,
    required this.onPreview,
    required this.onSelectDefault,
    required this.onEditLabel,
  });
  final Voice voice;
  final String label;
  final bool selected;
  final bool playing;
  final VoidCallback onPreview;
  final VoidCallback onSelectDefault;
  final VoidCallback onEditLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: selected
                ? Colors.teal
                : theme.dividerColor.withValues(alpha: 0.4),
            width: selected ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded,
                  color: Colors.teal, size: 20),
          ]),
          if (label != voice.name)
            Text(voice.name,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
          Row(children: [
            Icon(Icons.circle,
                size: 9,
                color: voice.active ? Colors.green : Colors.grey),
            const SizedBox(width: 4),
            Text(voice.active ? 'Active' : 'Inactive',
                style: theme.textTheme.bodySmall),
            const SizedBox(width: 10),
            Icon(Icons.language_rounded, size: 12, color: theme.hintColor),
            const SizedBox(width: 3),
            Text(voice.language, style: theme.textTheme.bodySmall),
          ]),
          if (voice.description != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(voice.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall),
            ),
          const Spacer(),
          Text('ID: ${voice.voiceId}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontFamily: 'monospace', color: theme.hintColor)),
          const Gap.v(AppSpacing.sm),
          Row(children: [
            OutlinedButton.icon(
              onPressed: onPreview,
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 10)),
              icon: Icon(playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  size: 16),
              label: Text(playing ? 'Stop' : 'Preview'),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Edit label',
              onPressed: onEditLabel,
              icon: const Icon(Icons.edit_rounded, size: 18),
            ),
            if (!selected)
              TextButton(
                  onPressed: onSelectDefault,
                  child: const Text('Select as Default')),
          ]),
        ],
      ),
    );
  }
}
