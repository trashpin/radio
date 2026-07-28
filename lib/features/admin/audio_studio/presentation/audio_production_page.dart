import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/audio_studio/data/audio_production_repository.dart';
import 'package:explorer_os_mobile/features/admin/audio_studio/logic/audio_audit.dart';
import 'package:explorer_os_mobile/features/admin/audio_studio/models/audio_asset.dart';
import 'package:explorer_os_mobile/features/admin/media_manager/presentation/widgets/media_widgets.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/content_generator/data/content_generator_repository.dart';
import 'package:explorer_os_mobile/features/destinations/providers/destinations_provider.dart';
import 'package:explorer_os_mobile/features/narration/voices.dart';
import 'package:explorer_os_mobile/shared/models/destination.dart';

/// Local (session) generation settings — provider, language, batch size.
class AudioSettings {
  const AudioSettings({
    this.provider = TtsProvider.elevenlabs,
    this.language = 'en',
    this.batchSize = 25,
  });
  final TtsProvider provider;
  final String language;
  final int batchSize;

  AudioSettings copyWith({TtsProvider? provider, String? language, int? batchSize}) =>
      AudioSettings(
        provider: provider ?? this.provider,
        language: language ?? this.language,
        batchSize: batchSize ?? this.batchSize,
      );
}

final audioSettingsProvider =
    NotifierProvider<AudioSettingsNotifier, AudioSettings>(
        AudioSettingsNotifier.new);

class AudioSettingsNotifier extends Notifier<AudioSettings> {
  @override
  AudioSettings build() => const AudioSettings();
  void set(AudioSettings s) => state = s;
}

/// The Audio Production Studio admin module.
class AudioProductionPage extends StatelessWidget {
  const AudioProductionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 7,
      child: Column(
        children: [
          Material(
            color: theme.colorScheme.surface,
            child: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: 'Dashboard'),
                Tab(text: 'Production Queue'),
                Tab(text: 'Voice Library'),
                Tab(text: 'Audio Library'),
                Tab(text: 'Batch Generator'),
                Tab(text: 'Audio Audit'),
                Tab(text: 'Settings'),
              ],
            ),
          ),
          const Divider(height: 1),
          const Expanded(
            child: TabBarView(
              physics: NeverScrollableScrollPhysics(),
              children: [
                _DashboardTab(),
                _QueueTab(),
                _VoiceLibraryTab(),
                _AudioLibraryTab(),
                _BatchTab(),
                _AuditTab(),
                _SettingsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Dashboard --------------------------------------------------------------

class _DashboardTab extends ConsumerWidget {
  const _DashboardTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(audioDashboardProvider);
    final rem = s.estimatedRemaining();
    String hm(Duration d) =>
        '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Audio Production',
          subtitle: 'Narration coverage across every record.',
        ),
        const Gap.v(AppSpacing.lg),
        LayoutBuilder(builder: (context, c) {
          final cols = (c.maxWidth / 220).floor().clamp(2, 4);
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
            childAspectRatio: 1.5,
            children: [
              AdminStatCard(label: 'Total Records', value: '${s.totalRecords}', icon: Icons.dataset_rounded),
              AdminStatCard(label: 'With Audio', value: '${s.recordsWithAudio}', icon: Icons.graphic_eq_rounded, tint: const Color(0xFF2E7D32)),
              AdminStatCard(label: 'Missing Audio', value: '${s.recordsMissingAudio}', icon: Icons.music_off_rounded, tint: const Color(0xFFB3261E)),
              AdminStatCard(label: 'Needs Regen', value: '${s.recordsNeedingRegen}', icon: Icons.autorenew_rounded, tint: const Color(0xFF8A6D00)),
              AdminStatCard(label: 'In Queue', value: '${s.queued}', icon: Icons.queue_rounded, tint: const Color(0xFF2C6E8F)),
              AdminStatCard(label: 'Storage Used', value: formatBytes(s.storageUsedBytes), icon: Icons.sd_storage_rounded),
              AdminStatCard(label: 'Est. Remaining', value: hm(rem), icon: Icons.timer_rounded, tint: const Color(0xFF6A5ACD)),
              AdminStatCard(label: 'Completion', value: '${s.completionPercent.round()}%', icon: Icons.verified_rounded, tint: const Color(0xFF2E7D32)),
            ],
          );
        }),
        const Gap.v(AppSpacing.xl),
        AdminSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Generation progress',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const Gap.v(AppSpacing.md),
              MediaProgress(
                  label: 'Records with narration',
                  value: s.completionPercent / 100,
                  color: const Color(0xFF2E7D32)),
            ],
          ),
        ),
      ],
    );
  }
}

// --- Production Queue -------------------------------------------------------

class _QueueTab extends ConsumerWidget {
  const _QueueTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final audits = ref.watch(audioAuditProvider);
    final defaults = ref.watch(voiceCategoryDefaultsProvider).value ?? const {};
    final queue = audits.where((a) => a.missingAudio).toList();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AdminPageHeader(
          title: 'Production Queue',
          subtitle: '${queue.length} records waiting for narration',
        ),
        const Gap.v(AppSpacing.md),
        AdminSectionCard(
          child: queue.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: AdminEmptyState(
                      icon: Icons.verified_rounded,
                      message: 'Every record has narration.'))
              : Column(children: [
                  for (final a in queue.take(200)) _row(context, ref, theme, a, defaults),
                ]),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, ThemeData theme,
      AudioRecordAudit a, Map<String, VoiceAssignment> defaults) {
    final voice = defaults[a.ref.category.id]?.voiceName ??
        voiceNameForId(kFallbackVoiceId);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)))),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.ref.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(a.ref.category.label, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Expanded(flex: 2, child: Text(voice ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall)),
          const SizedBox(width: 70, child: MediaStatusBadge('Pending', tone: MediaBadgeTone.warn)),
          const Gap.h(AppSpacing.sm),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
            onPressed: () => _generate(context, ref, a),
            icon: const Icon(Icons.graphic_eq_rounded, size: 16),
            label: const Text('Generate'),
          ),
        ],
      ),
    );
  }

  Future<void> _generate(BuildContext context, WidgetRef ref, AudioRecordAudit a) async {
    await ref.read(audioProductionRepositoryProvider).enqueueAudioJob(
          destination: a.ref.title,
          notes: 'audio:record;type=${a.ref.category.id};id=${a.ref.id}',
        );
    ref.read(contentRefreshProvider.notifier).bump();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Queued narration for ${a.ref.title}')));
    }
  }
}

// --- Voice Library ----------------------------------------------------------

class _VoiceLibraryTab extends ConsumerWidget {
  const _VoiceLibraryTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final defaults = ref.watch(voiceCategoryDefaultsProvider).value ?? const {};
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Voice Library',
          subtitle: 'Assign a default voice to each content category.',
        ),
        const Gap.v(AppSpacing.md),
        AdminSectionCard(
          child: Column(
            children: [
              for (final cat in VoiceCategory.values)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                          flex: 2,
                          child: Text(cat.label,
                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: defaults[cat.id]?.voiceId ??
                              (defaults.isEmpty ? null : null),
                          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                          hint: const Text('Default voice'),
                          items: [
                            for (final v in narrationVoices)
                              DropdownMenuItem(value: v.id, child: Text(v.name, overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (id) async {
                            if (id == null) return;
                            final name = voiceNameForId(id) ?? id;
                            final provider = ref.read(audioSettingsProvider).provider;
                            await ref.read(audioProductionRepositoryProvider)
                                .setVoiceForCategory(cat, id, name, provider);
                            ref.read(audioRefreshProvider.notifier).bump();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('${cat.label} → $name')));
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- Audio Library ----------------------------------------------------------

class _AudioLibraryTab extends ConsumerStatefulWidget {
  const _AudioLibraryTab();
  @override
  ConsumerState<_AudioLibraryTab> createState() => _AudioLibraryTabState();
}

class _AudioLibraryTabState extends ConsumerState<_AudioLibraryTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(audioAssetsProvider);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Audio Library',
          subtitle: 'Every generated narration file.',
        ),
        const Gap.v(AppSpacing.md),
        SizedBox(
          width: 260,
          child: TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search_rounded, size: 18),
              hintText: 'Search title / category…',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _query = v.toLowerCase()),
          ),
        ),
        const Gap.v(AppSpacing.md),
        async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => AdminSectionCard(
              child: AdminEmptyState(icon: Icons.error_outline_rounded, message: 'Could not load audio.\n$e')),
          data: (list) {
            final filtered = list.where((a) {
              if (_query.isEmpty) return true;
              return (a.category ?? '').toLowerCase().contains(_query) ||
                  (a.voiceName ?? '').toLowerCase().contains(_query) ||
                  (a.storagePath ?? '').toLowerCase().contains(_query);
            }).toList();
            return AdminSectionCard(
              child: filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: AdminEmptyState(
                          icon: Icons.library_music_rounded,
                          message: 'No audio yet. Generate narration from the '
                              'Batch Generator or Production Queue.'))
                  : Column(children: [for (final a in filtered) _tile(theme, a)]),
            );
          },
        ),
      ],
    );
  }

  Widget _tile(ThemeData theme, AudioAsset a) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)))),
      child: Row(
        children: [
          const _FauxWaveform(),
          const Gap.h(AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.storagePath ?? a.category ?? a.id,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text([
                  if (a.voiceName != null) a.voiceName,
                  a.provider.label,
                  if (a.duration != null) '${a.duration!.toStringAsFixed(0)}s',
                  if (a.fileSize != null) formatBytes(a.fileSize!),
                ].whereType<String>().join('  ·  '), style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Preview',
            onPressed: a.hasFile ? () => _preview(context, a) : null,
            icon: const Icon(Icons.play_circle_outline_rounded),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: () async {
              await ref.read(audioProductionRepositoryProvider).deleteAsset(a.id);
              ref.read(audioRefreshProvider.notifier).bump();
            },
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }

  void _preview(BuildContext context, AudioAsset a) {
    showDialog<void>(
      context: context,
      builder: (_) => _PreviewDialog(url: a.publicUrl!, title: a.storagePath ?? 'Preview'),
    );
  }
}

class _FauxWaveform extends StatelessWidget {
  const _FauxWaveform();
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary.withValues(alpha: 0.5);
    const heights = [8.0, 16.0, 24.0, 14.0, 30.0, 12.0, 20.0, 10.0, 26.0, 16.0];
    return SizedBox(
      width: 72,
      height: 32,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final h in heights)
            Container(
              width: 4,
              height: h,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
            ),
        ],
      ),
    );
  }
}

class _PreviewDialog extends StatefulWidget {
  const _PreviewDialog({required this.url, required this.title});
  final String url;
  final String title;
  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  final _player = AudioPlayer();
  String? _error;

  @override
  void initState() {
    super.initState();
    _player.setUrl(widget.url).then((_) => _player.play()).catchError((e) {
      if (mounted) setState(() => _error = '$e');
      return null;
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      content: _error != null
          ? Text('Could not play: $_error')
          : StreamBuilder<PlayerState>(
              stream: _player.playerStateStream,
              builder: (_, snap) {
                final playing = snap.data?.playing ?? false;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      iconSize: 40,
                      onPressed: () => playing ? _player.pause() : _player.play(),
                      icon: Icon(playing ? Icons.pause_circle : Icons.play_circle),
                    ),
                    const Gap.h(AppSpacing.sm),
                    const Expanded(child: _FauxWaveform()),
                  ],
                );
              },
            ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}

// --- Batch Generator --------------------------------------------------------

class _BatchTab extends ConsumerStatefulWidget {
  const _BatchTab();
  @override
  ConsumerState<_BatchTab> createState() => _BatchTabState();
}

class _BatchTabState extends ConsumerState<_BatchTab> {
  VoiceCategory _category = VoiceCategory.wildlife;
  Destination? _destination;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final queued = ref.watch(audioQueueCountProvider);
    final dashboard = ref.watch(audioDashboardProvider);
    final destinations = (ref.watch(destinationsProvider).value ?? const [])
        .where((d) => d.latitude != null)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Batch Generator',
          subtitle: 'Queue narration in bulk. Jobs are drained by the worker '
              'to respect provider rate limits.',
        ),
        const Gap.v(AppSpacing.md),
        AdminSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MediaProgress(
                label: 'In queue',
                value: queued == 0 ? 0 : (queued / (queued + dashboard.recordsWithAudio + 1)),
                trailing: '$queued jobs',
              ),
              const Gap.v(AppSpacing.lg),
              Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
                _btn('Generate Missing Audio (${dashboard.recordsMissingAudio})',
                    Icons.playlist_add_rounded,
                    () => _enqueue('audio:missing', 'All missing narration')),
                _btn('Generate Entire Library', Icons.all_inclusive_rounded,
                    () => _enqueue('audio:all', 'Entire library')),
              ]),
              const Divider(height: AppSpacing.xl),
              _rowControl(
                theme,
                'Generate Category',
                DropdownButton<VoiceCategory>(
                  value: _category,
                  items: [for (final c in VoiceCategory.values) DropdownMenuItem(value: c, child: Text(c.label))],
                  onChanged: (c) => setState(() => _category = c ?? _category),
                ),
                () => _enqueue('audio:category;type=${_category.id}', '${_category.label} category'),
              ),
              const Gap.v(AppSpacing.md),
              _rowControl(
                theme,
                'Generate / Publish Destination',
                DropdownButton<Destination>(
                  value: _destination,
                  hint: const Text('Choose destination'),
                  items: [for (final d in destinations) DropdownMenuItem(value: d, child: Text(d.name, overflow: TextOverflow.ellipsis))],
                  onChanged: (d) => setState(() => _destination = d),
                ),
                _destination == null ? null : () => _publish(_destination!),
                actionLabel: 'Publish',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _rowControl(ThemeData theme, String label, Widget control,
      VoidCallback? onAction, {String actionLabel = 'Generate'}) {
    return Row(
      children: [
        Expanded(flex: 2, child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
        Expanded(flex: 3, child: Align(alignment: Alignment.centerLeft, child: control)),
        FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }

  Widget _btn(String label, IconData icon, VoidCallback onTap) => FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );

  Future<void> _enqueue(String notes, String label) async {
    await ref.read(audioProductionRepositoryProvider)
        .enqueueAudioJob(destination: label, notes: notes);
    ref.read(contentRefreshProvider.notifier).bump();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Queued: $label')));
    }
  }

  Future<void> _publish(Destination d) async {
    await ref.read(audioProductionRepositoryProvider).publishDestination(d.id, d.name);
    ref.read(contentRefreshProvider.notifier).bump();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Publishing ${d.name} — full narration set queued')));
    }
  }
}

// --- Audio Audit ------------------------------------------------------------

class _AuditTab extends ConsumerWidget {
  const _AuditTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final audits = ref.watch(audioAuditProvider);
    final issues = audits.where((a) => a.hasIssue).toList();
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AdminPageHeader(
          title: 'Audio Audit',
          subtitle: '${issues.length} of ${audits.length} records need attention',
          actions: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: audits.isEmpty ? null : () => _export(context, audioCsv(audits)),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Export CSV'),
            ),
          ],
        ),
        const Gap.v(AppSpacing.md),
        AdminSectionCard(
          child: issues.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: AdminEmptyState(icon: Icons.verified_rounded, message: 'No audio issues.'))
              : Column(children: [for (final a in issues.take(300)) _row(theme, a)]),
        ),
      ],
    );
  }

  Widget _row(ThemeData theme, AudioRecordAudit a) {
    final flags = <Widget>[
      if (a.missingAudio) const MediaStatusBadge('Missing', tone: MediaBadgeTone.missing),
      if (a.needsRegen) const MediaStatusBadge('Outdated', tone: MediaBadgeTone.warn),
      if (a.broken) const MediaStatusBadge('Broken', tone: MediaBadgeTone.missing),
      if (a.zeroByte) const MediaStatusBadge('0 bytes', tone: MediaBadgeTone.missing),
      if (a.duplicate) const MediaStatusBadge('Duplicate', tone: MediaBadgeTone.warn),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)))),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.ref.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(a.ref.category.label, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Expanded(flex: 4, child: Wrap(spacing: 4, runSpacing: 4, children: flags)),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context, String csv) async {
    await Clipboard.setData(ClipboardData(text: csv));
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Audio audit CSV'),
        content: SizedBox(
          width: 560,
          height: 360,
          child: SingleChildScrollView(
            child: SelectableText(csv, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV copied to clipboard.')));
  }
}

// --- Settings ---------------------------------------------------------------

class _SettingsTab extends ConsumerWidget {
  const _SettingsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = ref.watch(audioSettingsProvider);
    final notifier = ref.read(audioSettingsProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Settings',
          subtitle: 'Provider, language and batching.',
        ),
        const Gap.v(AppSpacing.md),
        AdminSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field(theme, 'TTS provider',
                DropdownButton<TtsProvider>(
                  value: s.provider,
                  items: [for (final p in TtsProvider.values) DropdownMenuItem(value: p, child: Text(p.label))],
                  onChanged: (p) => notifier.set(s.copyWith(provider: p)),
                )),
              _field(theme, 'Language',
                DropdownButton<String>(
                  value: s.language,
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(value: 'es', child: Text('Spanish')),
                    DropdownMenuItem(value: 'fr', child: Text('French')),
                    DropdownMenuItem(value: 'de', child: Text('German')),
                  ],
                  onChanged: (l) => notifier.set(s.copyWith(language: l)),
                )),
              _field(theme, 'Batch size',
                DropdownButton<int>(
                  value: s.batchSize,
                  items: const [10, 25, 50, 100].map((n) => DropdownMenuItem(value: n, child: Text('$n'))).toList(),
                  onChanged: (n) => notifier.set(s.copyWith(batchSize: n)),
                )),
              const Divider(height: AppSpacing.xl),
              Text('Providers (selectable without code changes)',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const Gap.v(AppSpacing.sm),
              Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
                for (final p in TtsProvider.values)
                  MediaStatusBadge(p.label,
                      tone: p == s.provider ? MediaBadgeTone.ok : MediaBadgeTone.info),
              ]),
              const Gap.v(AppSpacing.md),
              Text('Generation version: v$kAudioGenerationVersion  ·  '
                  'Storage bucket: audio (public)', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(ThemeData theme, String label, Widget control) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(width: 150, child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.disabledColor))),
          Expanded(child: Align(alignment: Alignment.centerLeft, child: control)),
        ]),
      );
}
