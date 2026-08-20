import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/dj/banter/banter_engine.dart';
import 'package:explorer_os_mobile/features/dj/models/dj_personality.dart';
import 'package:explorer_os_mobile/features/narration/data/voice_repository.dart';
import 'package:explorer_os_mobile/features/radio_automation/data/radio_automation_repository.dart';
import 'package:explorer_os_mobile/features/radio_automation/models/radio_schedule_rule.dart';
import 'package:explorer_os_mobile/features/radio_automation/models/radio_segment.dart';

/// Admin → Radio Automation: a professional-style segment library + scheduler.
/// Library (all segments, filterable), Create (AI/template segment generator),
/// Schedule (trigger rules), Voices, and Templates — all backed by
/// `radio_segments` / `radio_schedule_rules`, and played by the runtime.
class RadioAutomationPage extends StatelessWidget {
  const RadioAutomationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          Material(
            color: theme.colorScheme.surface,
            child: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(icon: Icon(Icons.library_music_rounded), text: 'Library'),
                Tab(icon: Icon(Icons.auto_awesome_rounded), text: 'Create'),
                Tab(icon: Icon(Icons.schedule_rounded), text: 'Schedule'),
                Tab(icon: Icon(Icons.graphic_eq_rounded), text: 'Voices'),
                Tab(icon: Icon(Icons.dashboard_customize_rounded), text: 'Templates'),
              ],
            ),
          ),
          const Divider(height: 1),
          const Expanded(
            child: TabBarView(
              physics: NeverScrollableScrollPhysics(),
              children: [
                _LibraryTab(),
                _CreateTab(),
                _ScheduleTab(),
                _VoicesTab(),
                _TemplatesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Library ──────────────────────────────────────────────────────────────────

class _LibraryTab extends ConsumerStatefulWidget {
  const _LibraryTab();
  @override
  ConsumerState<_LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends ConsumerState<_LibraryTab> {
  SegmentCategory? _category;
  String? _station;
  bool _publishedOnly = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(radioSegmentsProvider);
    final repo = ref.read(radioAutomationRepositoryProvider);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Segment Library',
          subtitle: 'Every DJ banter, station ID, intro/outro, and promo — '
              'searchable, playable, and schedulable.',
        ),
        const Gap.v(AppSpacing.lg),
        // Filters
        Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<SegmentCategory?>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Category', isDense: true, border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: null, child: Text('All categories')),
                for (final c in SegmentCategory.values)
                  DropdownMenuItem(value: c, child: Text(c.label)),
              ],
              onChanged: (v) => setState(() => _category = v),
            ),
          ),
          SizedBox(
            width: 160,
            child: DropdownButtonFormField<String?>(
              initialValue: _station,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Station', isDense: true, border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: null, child: Text('All stations')),
                for (final s in DjStation.values)
                  DropdownMenuItem(value: s.name, child: Text(s.label)),
              ],
              onChanged: (v) => setState(() => _station = v),
            ),
          ),
          FilterChip(
            label: const Text('Published only'),
            selected: _publishedOnly,
            onSelected: (v) => setState(() => _publishedOnly = v),
          ),
        ]),
        const Gap.v(AppSpacing.lg),
        async.when(
          loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator())),
          error: (e, _) => AdminSectionCard(
              child: AdminEmptyState(
                  icon: Icons.error_outline_rounded,
                  message: 'Could not load segments.\n$e')),
          data: (all) {
            final rows = all.where((s) {
              if (_category != null && s.category != _category) return false;
              if (_station != null && s.station != _station) return false;
              if (_publishedOnly && !s.published) return false;
              return true;
            }).toList();
            if (rows.isEmpty) {
              return const AdminSectionCard(
                  child: AdminEmptyState(
                      icon: Icons.library_music_rounded,
                      message: 'No segments. Create one in the "Create" tab — '
                          'audio generates automatically, or use "Generate '
                          'Audio" here for any segment without one yet.'));
            }
            return AdminSectionCard(
              child: Column(children: [
                for (final s in rows) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(s.category.icon,
                        color: s.hasAudio ? Colors.teal : theme.disabledColor),
                    title: Text(s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      s.category.label,
                      s.station,
                      if (s.voice != null) s.voice!,
                      if (s.duration != null) '${s.duration}s',
                      'plays: ${s.playCount}',
                    ].join('  ·  '),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      StatusBadge(s.published
                          ? BadgeStatus.published
                          : BadgeStatus.draft),
                      if (s.hasAudio)
                        IconButton(
                          tooltip: 'Preview',
                          icon: const Icon(Icons.play_circle_outline_rounded),
                          onPressed: () => _preview(context, s),
                        ),
                      PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'publish') {
                            await repo.setPublished(s.id, !s.published);
                          } else if (v == 'duplicate') {
                            await repo.duplicateSegment(s);
                          } else if (v == 'delete') {
                            await repo.deleteSegment(s.id);
                          } else if (v == 'generate_audio') {
                            final queued =
                                await repo.enqueueSegmentAudio(s.id, voiceId: s.voiceId);
                            if (queued) await repo.triggerNarrationWorker();
                          }
                          ref.read(segmentsRefreshProvider.notifier).bump();
                        },
                        itemBuilder: (_) => [
                          if (!s.hasAudio)
                            const PopupMenuItem(
                                value: 'generate_audio',
                                child: Text('Generate Audio')),
                          PopupMenuItem(
                              value: 'publish',
                              child: Text(s.published ? 'Unpublish' : 'Publish')),
                          const PopupMenuItem(
                              value: 'duplicate', child: Text('Duplicate')),
                          const PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ]),
                  ),
                  const Divider(height: 1),
                ],
              ]),
            );
          },
        ),
      ],
    );
  }

  void _preview(BuildContext context, RadioSegment s) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.title),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (s.script != null)
              Text('"${s.script}"',
                  style: const TextStyle(fontStyle: FontStyle.italic)),
            const Gap.v(AppSpacing.md),
            if (s.hasAudio) _ClipPlayer(url: s.audioUrl!),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }
}

/// Minimal inline audio player for previewing a segment.
class _ClipPlayer extends StatefulWidget {
  const _ClipPlayer({required this.url});
  final String url;
  @override
  State<_ClipPlayer> createState() => _ClipPlayerState();
}

class _ClipPlayerState extends State<_ClipPlayer> {
  final _player = AudioPlayer();
  String? _error;

  @override
  void initState() {
    super.initState();
    _player.setUrl(widget.url).catchError((e) {
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
    if (_error != null) return Text('Could not load audio.\n$_error');
    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (context, snap) {
        final playing = snap.data?.playing ?? false;
        return Row(children: [
          IconButton.filled(
            iconSize: 30,
            onPressed: () => playing ? _player.pause() : _player.play(),
            icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
          ),
          const Gap.h(AppSpacing.sm),
          const Expanded(child: Text('Segment audio')),
        ]);
      },
    );
  }
}

// ── Create ───────────────────────────────────────────────────────────────────

class _CreateTab extends ConsumerStatefulWidget {
  const _CreateTab();
  @override
  ConsumerState<_CreateTab> createState() => _CreateTabState();
}

class _CreateTabState extends ConsumerState<_CreateTab> {
  SegmentCategory _category = SegmentCategory.djBanter;
  DjStation _station = DjStation.country;
  final _topic = TextEditingController();
  final _title = TextEditingController();
  final _script = TextEditingController();
  String? _voiceId;
  String? _voiceName;
  bool _saving = false;
  String? _message;

  static const _situation = {
    SegmentCategory.djBanter: BanterSituation.songOutro,
    SegmentCategory.songIntro: BanterSituation.songIntro,
    SegmentCategory.songOutro: BanterSituation.songOutro,
    SegmentCategory.stationId: BanterSituation.stationId,
    SegmentCategory.promo: BanterSituation.stationId,
    SegmentCategory.weather: BanterSituation.weather,
    SegmentCategory.safety: BanterSituation.safetyReminder,
    SegmentCategory.gpsTransition: BanterSituation.gpsApproaching,
    SegmentCategory.wildlifeIntro: BanterSituation.wildlifeSighting,
  };

  @override
  void dispose() {
    _topic.dispose();
    _title.dispose();
    _script.dispose();
    super.dispose();
  }

  void _generate() {
    final engine = BanterEngine(rng: Random());
    final ctx = BanterContext(
      theme: _topic.text.trim().isEmpty ? null : _topic.text.trim(),
      songTitle: _category == SegmentCategory.songIntro ||
              _category == SegmentCategory.songOutro
          ? (_topic.text.trim().isEmpty ? null : _topic.text.trim())
          : null,
    );
    final line = engine.generate(
        _station, _situation[_category] ?? BanterSituation.stationId, ctx);
    setState(() {
      _script.text = line ?? '';
      if (_title.text.trim().isEmpty) {
        _title.text = '${_category.label} — ${_station.label}';
      }
    });
  }

  Future<void> _save() async {
    if (_script.text.trim().isEmpty) {
      setState(() => _message = 'Generate or write a script first.');
      return;
    }
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final repo = ref.read(radioAutomationRepositoryProvider);
      final id = await repo.insertSegment(RadioSegment(
            id: '',
            title: _title.text.trim().isEmpty
                ? '${_category.label} — ${_station.label}'
                : _title.text.trim(),
            category: _category,
            station: _station.name,
            voice: _voiceName,
            voiceId: _voiceId,
            script: _script.text.trim(),
            generatedByAi: true,
            published: false,
          ));
      ref.read(segmentsRefreshProvider.notifier).bump();

      // Voice it right away, the same "enqueue + trigger the worker now"
      // pattern the Nearby Gems admin's "Generate Narration" button already
      // uses — no ElevenLabs key ever touches this client.
      final queued = await repo.enqueueSegmentAudio(id, voiceId: _voiceId);
      if (!queued) {
        setState(() {
          _message = 'Saved to the library (draft). Could not queue audio '
              '(Supabase not configured) — try "Generate Audio" from the '
              'Library tab later.';
          _saving = false;
        });
        return;
      }
      final triggered = await repo.triggerNarrationWorker();
      String? url = await repo.audioUrlFor(id);
      if (url == null && triggered) {
        for (var i = 0; i < 5 && url == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 1500));
          url = await repo.audioUrlFor(id);
        }
      }
      ref.read(segmentsRefreshProvider.notifier).bump();
      setState(() {
        _message = url != null
            ? 'Saved and voiced — open the Library tab to preview and publish.'
            : 'Saved — audio is generating in the background and will '
                'appear in the Library tab shortly.';
        _saving = false;
      });
    } catch (e) {
      setState(() {
        _saving = false;
        _message = 'Save failed (signed in? migration 0016 run?): $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final voices = ref.watch(voicesProvider).value ?? const [];
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Create Segment',
          subtitle: 'Generate a script from templates, edit it, and save — '
              'audio is voiced automatically with ElevenLabs.',
        ),
        const Gap.v(AppSpacing.lg),
        AdminSectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<SegmentCategory>(
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Category', isDense: true, border: OutlineInputBorder()),
                  items: [
                    for (final c in SegmentCategory.values)
                      DropdownMenuItem(value: c, child: Text(c.label)),
                  ],
                  onChanged: (v) => setState(() => _category = v ?? _category),
                ),
              ),
              const Gap.h(AppSpacing.sm),
              Expanded(
                child: DropdownButtonFormField<DjStation>(
                  initialValue: _station,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Station', isDense: true, border: OutlineInputBorder()),
                  items: [
                    for (final s in DjStation.values)
                      DropdownMenuItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: (v) => setState(() => _station = v ?? _station),
                ),
              ),
            ]),
            const Gap.v(AppSpacing.sm),
            TextField(
              controller: _topic,
              decoration: const InputDecoration(
                  labelText: 'Topic / theme (or song title for intros)',
                  isDense: true,
                  border: OutlineInputBorder()),
            ),
            const Gap.v(AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: _voiceId,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Voice', isDense: true, border: OutlineInputBorder()),
              items: [
                for (final v in voices)
                  DropdownMenuItem(value: v.voiceId, child: Text(v.name)),
              ],
              onChanged: (id) {
                if (id == null) return;
                final v = voices.firstWhere((x) => x.voiceId == id);
                setState(() {
                  _voiceId = v.voiceId;
                  _voiceName = v.name;
                });
              },
            ),
            const Gap.v(AppSpacing.md),
            OutlinedButton.icon(
              onPressed: _generate,
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text('Generate script'),
            ),
            const Gap.v(AppSpacing.md),
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                  labelText: 'Title', isDense: true, border: OutlineInputBorder()),
            ),
            const Gap.v(AppSpacing.sm),
            TextField(
              controller: _script,
              maxLines: 4,
              decoration: const InputDecoration(
                  labelText: 'Script', border: OutlineInputBorder()),
            ),
            const Gap.v(AppSpacing.md),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.graphic_eq_rounded, size: 18),
              label: const Text('Save & generate audio'),
            ),
            if (_message != null) ...[
              const Gap.v(AppSpacing.sm),
              Text(_message!, style: theme.textTheme.bodySmall),
            ],
          ]),
        ),
      ],
    );
  }
}

// ── Schedule ────────────────────────────────────────────────────────────────

class _ScheduleTab extends ConsumerWidget {
  const _ScheduleTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(radioRulesProvider);
    final repo = ref.read(radioAutomationRepositoryProvider);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AdminPageHeader(
          title: 'Scheduled Events',
          subtitle: 'Rules that decide when segments play (every N songs/minutes, '
              'top of hour, GPS arrival, sunrise/sunset, and more).',
          actions: [
            FilledButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                    context: context, builder: (_) => const _RuleDialog());
                if (ok == true) ref.read(segmentsRefreshProvider.notifier).bump();
              },
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add rule'),
            ),
          ],
        ),
        const Gap.v(AppSpacing.lg),
        async.when(
          loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator())),
          error: (e, _) => AdminSectionCard(
              child: AdminEmptyState(
                  icon: Icons.error_outline_rounded,
                  message: 'Could not load rules.\n$e')),
          data: (rules) => rules.isEmpty
              ? const AdminSectionCard(
                  child: AdminEmptyState(
                      icon: Icons.schedule_rounded,
                      message: 'No rules yet. Click "Add rule".'))
              : AdminSectionCard(
                  child: Column(children: [
                    for (final r in rules) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.rule_rounded,
                            color: r.enabled ? Colors.teal : theme.disabledColor),
                        title: Text(r.name,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        subtitle: Text([
                          r.triggerType.label,
                          if (r.triggerValue != null) '${r.triggerValue}',
                          r.station,
                          if (r.category != null) r.category!,
                          'priority ${r.priority}',
                          r.daypart.label,
                        ].join('  ·  ')),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          Switch(
                            value: r.enabled,
                            onChanged: (v) async {
                              await repo.setRuleEnabled(r.id, v);
                              ref.read(segmentsRefreshProvider.notifier).bump();
                            },
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () async {
                              await repo.deleteRule(r.id);
                              ref.read(segmentsRefreshProvider.notifier).bump();
                            },
                          ),
                        ]),
                      ),
                      const Divider(height: 1),
                    ],
                  ]),
                ),
        ),
      ],
    );
  }
}

class _RuleDialog extends ConsumerStatefulWidget {
  const _RuleDialog();
  @override
  ConsumerState<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends ConsumerState<_RuleDialog> {
  final _name = TextEditingController();
  DjStation _station = DjStation.all;
  SegmentCategory _category = SegmentCategory.djBanter;
  TriggerType _trigger = TriggerType.everyXSongs;
  final _value = TextEditingController(text: '3');
  Daypart _daypart = Daypart.any;
  final _priority = TextEditingController(text: '5');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    _priority.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(radioAutomationRepositoryProvider).insertRule(RadioScheduleRule(
            id: '',
            name: _name.text.trim(),
            station: _station.name,
            category: _category.dbValue,
            triggerType: _trigger,
            triggerValue:
                _trigger.needsValue ? int.tryParse(_value.text.trim()) : null,
            daypart: _daypart,
            priority: int.tryParse(_priority.text.trim()) ?? 5,
            enabled: true,
          ));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Save failed (migration 0016 run?): $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add schedule rule'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: 'Rule name', border: OutlineInputBorder())),
            const Gap.v(AppSpacing.sm),
            DropdownButtonFormField<TriggerType>(
              initialValue: _trigger,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Trigger', border: OutlineInputBorder()),
              items: [
                for (final t in TriggerType.values)
                  DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: (t) => setState(() => _trigger = t ?? _trigger),
            ),
            if (_trigger.needsValue) ...[
              const Gap.v(AppSpacing.sm),
              TextField(
                  controller: _value,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Value (N)', border: OutlineInputBorder())),
            ],
            const Gap.v(AppSpacing.sm),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<SegmentCategory>(
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Plays category', isDense: true, border: OutlineInputBorder()),
                  items: [
                    for (final c in SegmentCategory.values)
                      DropdownMenuItem(value: c, child: Text(c.label)),
                  ],
                  onChanged: (c) => setState(() => _category = c ?? _category),
                ),
              ),
              const Gap.h(AppSpacing.sm),
              Expanded(
                child: DropdownButtonFormField<DjStation>(
                  initialValue: _station,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Station', isDense: true, border: OutlineInputBorder()),
                  items: [
                    for (final s in DjStation.values)
                      DropdownMenuItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: (s) => setState(() => _station = s ?? _station),
                ),
              ),
            ]),
            const Gap.v(AppSpacing.sm),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<Daypart>(
                  initialValue: _daypart,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Daypart', isDense: true, border: OutlineInputBorder()),
                  items: [
                    for (final d in Daypart.values)
                      DropdownMenuItem(value: d, child: Text(d.label)),
                  ],
                  onChanged: (d) => setState(() => _daypart = d ?? _daypart),
                ),
              ),
              const Gap.h(AppSpacing.sm),
              Expanded(
                child: TextField(
                    controller: _priority,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Priority', isDense: true, border: OutlineInputBorder())),
              ),
            ]),
            if (_error != null) ...[
              const Gap.v(AppSpacing.sm),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Save')),
      ],
    );
  }
}

// ── Voices ───────────────────────────────────────────────────────────────────

class _VoicesTab extends ConsumerWidget {
  const _VoicesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final roster = ref.watch(djRosterProvider);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Station Voices',
          subtitle: 'Each station\'s default DJ voice. Assign voices in the DJ '
              'Studio; generate their audio with tool/dj_audio.dart.',
        ),
        const Gap.v(AppSpacing.lg),
        AdminSectionCard(
          child: Column(children: [
            for (final dj in roster) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.headset_mic_rounded),
                title: Text(dj.name,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                subtitle: Text('${dj.station.label} · ${dj.personality}'),
                trailing: StatusBadge(
                  dj.voiceId != null ? BadgeStatus.published : BadgeStatus.draft,
                  label: dj.voiceName ?? 'No voice',
                ),
              ),
              const Divider(height: 1),
            ],
          ]),
        ),
      ],
    );
  }
}

// ── Templates ─────────────────────────────────────────────────────────────────

class _TemplatesTab extends StatelessWidget {
  const _TemplatesTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byS = <BanterSituation, List<BanterTemplate>>{};
    for (final t in kBanterTemplates) {
      byS.putIfAbsent(t.situation, () => []).add(t);
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Banter Templates',
          subtitle: 'The template library the Create tool fills with live '
              'context. Placeholders like {song_title} and {park} are filled at '
              'generation time.',
        ),
        const Gap.v(AppSpacing.lg),
        for (final s in byS.keys) ...[
          AdminSectionCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.label,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Gap.v(AppSpacing.sm),
              for (final t in byS[s]!) ...[
                Text('• [${t.station.label}] ${t.text}',
                    style: theme.textTheme.bodySmall),
                const Gap.v(AppSpacing.xs),
              ],
            ]),
          ),
          const Gap.v(AppSpacing.md),
        ],
      ],
    );
  }
}
