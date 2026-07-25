import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/discovery/models/discovery_category.dart';
import 'package:explorer_os_mobile/features/narration/data/voice_repository.dart';
import 'package:explorer_os_mobile/features/narration/models/voice.dart';

/// Admin → Voice Manager: browse ElevenLabs voices, preview them, pick a default
/// per content category, and set the voice that "Generate Audio" uses. Selected
/// voice name + id are stored with each generated narration by the pipeline.
class VoiceManagerPage extends ConsumerStatefulWidget {
  const VoiceManagerPage({super.key});

  @override
  ConsumerState<VoiceManagerPage> createState() => _VoiceManagerPageState();
}

class _VoiceManagerPageState extends ConsumerState<VoiceManagerPage> {
  final AudioPlayer _player = AudioPlayer();
  String? _previewing; // voice_id currently playing

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

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(voicesProvider);
    final selected = ref.watch(selectedVoiceProvider);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AdminPageHeader(
          title: 'Voice Manager',
          subtitle: 'ElevenLabs voices — preview, assign, and set the '
              'default used by Generate Audio',
          actions: [
            FilledButton.icon(
              onPressed: () => refreshVoices(ref),
              style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg)),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
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
                child: Text('Generate Audio will use: ${selected.name}',
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
          data: (voices) => LayoutBuilder(builder: (context, c) {
            final cols = (c.maxWidth / 320).floor().clamp(1, 4);
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.md,
              childAspectRatio: 1.35,
              children: [
                for (final v in voices)
                  _VoiceCard(
                    voice: v,
                    selected: selected?.voiceId == v.voiceId,
                    playing: _previewing == v.voiceId,
                    onPreview: () => _preview(v),
                    onUseDefault: () =>
                        ref.read(selectedVoiceProvider.notifier).select(v),
                    onAssign: (cat) => ref
                        .read(categoryVoicesProvider.notifier)
                        .assign(cat, v.voiceId),
                  ),
              ],
            );
          }),
        ),
        const Gap.v(AppSpacing.lg),
        _categoryDefaults(),
      ],
    );
  }

  Widget _categoryDefaults() {
    final map = ref.watch(categoryVoicesProvider);
    final voices = ref.watch(voicesProvider).value ?? const [];
    if (voices.isEmpty) return const SizedBox.shrink();
    String nameFor(String id) =>
        voices.firstWhere((v) => v.voiceId == id, orElse: () => voices.first)
            .name;
    final assigned = discoveryCategories
        .where((c) => map.containsKey(c.token))
        .toList();
    return AdminSectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Default voice per category',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const Gap.v(AppSpacing.sm),
        if (assigned.isEmpty)
          const Text('No category defaults yet — use "Assign to category" on a voice.')
        else
          Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.sm, children: [
            for (final c in assigned)
              Chip(
                avatar: Icon(c.icon, size: 16, color: c.color),
                label: Text('${c.label}: ${nameFor(map[c.token]!)}'),
              ),
          ]),
      ]),
    );
  }
}

class _VoiceCard extends StatelessWidget {
  const _VoiceCard({
    required this.voice,
    required this.selected,
    required this.playing,
    required this.onPreview,
    required this.onUseDefault,
    required this.onAssign,
  });
  final Voice voice;
  final bool selected;
  final bool playing;
  final VoidCallback onPreview;
  final VoidCallback onUseDefault;
  final void Function(String category) onAssign;

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
              child: Text(voice.name,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded,
                  color: Colors.teal, size: 20),
          ]),
          if (voice.gender != null || voice.style != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Wrap(spacing: 6, children: [
                for (final t in [voice.gender, voice.style].whereType<String>())
                  Text('#$t',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.hintColor)),
              ]),
            ),
          if (voice.description != null)
            Expanded(
              child: Text(voice.description!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall),
            ),
          const Gap.v(AppSpacing.sm),
          Text('ID: ${voice.voiceId}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace', color: theme.hintColor)),
          const Gap.v(AppSpacing.sm),
          Row(children: [
            OutlinedButton.icon(
              onPressed: onPreview,
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12)),
              icon: Icon(playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  size: 18),
              label: Text(playing ? 'Stop' : 'Preview'),
            ),
            const Spacer(),
            if (!selected)
              TextButton(
                  onPressed: onUseDefault, child: const Text('Use')),
            PopupMenuButton<String>(
              tooltip: 'Assign to category',
              icon: const Icon(Icons.more_vert_rounded, size: 18),
              onSelected: onAssign,
              itemBuilder: (_) => [
                for (final c in discoveryCategories)
                  PopupMenuItem(value: c.token, child: Text('→ ${c.label}')),
              ],
            ),
          ]),
        ],
      ),
    );
  }
}
