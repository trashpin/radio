import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/dj/banter/banter_engine.dart';
import 'package:explorer_os_mobile/features/dj/models/dj_personality.dart';
import 'package:explorer_os_mobile/features/narration/data/voice_repository.dart';

/// Admin → DJ Studio. Three tools so stations sound like a programmed FM
/// station: manage DJ personalities (and their voices), generate situational
/// banter, and generate rotating song intros — all from templates + context
/// (no per-clip authoring).
class DjStudioPage extends StatelessWidget {
  const DjStudioPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Material(
            color: theme.colorScheme.surface,
            child: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(icon: Icon(Icons.record_voice_over_rounded), text: 'DJ Personalities'),
                Tab(icon: Icon(Icons.auto_awesome_rounded), text: 'Banter Generator'),
                Tab(icon: Icon(Icons.queue_music_rounded), text: 'Song Intro Generator'),
              ],
            ),
          ),
          const Divider(height: 1),
          const Expanded(
            child: TabBarView(
              physics: NeverScrollableScrollPhysics(),
              children: [
                _PersonalitiesTab(),
                _BanterTab(),
                _SongIntroTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── DJ Personalities ─────────────────────────────────────────────────────────

class _PersonalitiesTab extends ConsumerWidget {
  const _PersonalitiesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final roster = ref.watch(djRosterProvider);
    final voices = ref.watch(voicesProvider).value ?? const [];
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'DJ Personalities',
          subtitle:
              'Your on-air hosts. Assign each a voice; personality, energy and '
              'humor shape their banter style.',
        ),
        const Gap.v(AppSpacing.lg),
        for (final dj in roster) ...[
          AdminSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                    child: Icon(Icons.headset_mic_rounded,
                        color: theme.colorScheme.primary),
                  ),
                  const Gap.h(AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(dj.name,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        Text('${dj.station.label} · ${dj.tagline}',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  StatusBadge(
                    dj.voiceId != null ? BadgeStatus.published : BadgeStatus.draft,
                    label: dj.voiceId != null
                        ? 'Voice: ${dj.voiceName}'
                        : 'No voice',
                  ),
                ]),
                const Gap.v(AppSpacing.sm),
                Text(dj.personality, style: theme.textTheme.bodyMedium),
                const Gap.v(AppSpacing.sm),
                Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.xs, children: [
                  _meter('Energy', dj.energy),
                  _meter('Humor', dj.humor),
                  _chip('Banter: ${dj.length.label}'),
                ]),
                const Gap.v(AppSpacing.md),
                Row(children: [
                  const Icon(Icons.graphic_eq_rounded, size: 18),
                  const Gap.h(AppSpacing.sm),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: dj.voiceId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'ElevenLabs voice',
                          isDense: true,
                          border: OutlineInputBorder()),
                      items: [
                        for (final v in voices)
                          DropdownMenuItem(
                              value: v.voiceId, child: Text(v.name)),
                      ],
                      onChanged: (id) {
                        if (id == null) return;
                        final v = voices.firstWhere((x) => x.voiceId == id);
                        ref
                            .read(djVoiceAssignmentsProvider.notifier)
                            .assign(dj.id, v.voiceId, v.name);
                      },
                    ),
                  ),
                ]),
              ],
            ),
          ),
          const Gap.v(AppSpacing.md),
        ],
      ],
    );
  }

  Widget _meter(String label, int value) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label ', style: const TextStyle(fontWeight: FontWeight.w600)),
          for (var i = 1; i <= 5; i++)
            Icon(i <= value ? Icons.circle : Icons.circle_outlined, size: 10),
        ],
      );

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.teal.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Colors.teal, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

// ── Banter Generator ───────────────────────────────────────────────────────

class _BanterTab extends ConsumerStatefulWidget {
  const _BanterTab();
  @override
  ConsumerState<_BanterTab> createState() => _BanterTabState();
}

class _BanterTabState extends ConsumerState<_BanterTab> {
  DjStation _station = DjStation.country;
  BanterSituation _situation = BanterSituation.openingShow;
  final _song = TextEditingController(text: 'Rolling Through the Pines');
  final _artist = TextEditingController(text: 'Country Casey');
  final _landmark = TextEditingController(text: 'Juniper Springs');
  final _wildlife = TextEditingController(text: 'white-tailed deer');
  String? _output;

  @override
  void dispose() {
    _song.dispose();
    _artist.dispose();
    _landmark.dispose();
    _wildlife.dispose();
    super.dispose();
  }

  void _generate() {
    final roster = ref.read(djRosterProvider);
    final dj = djForStation(roster, _station);
    final engine = BanterEngine(rng: Random());
    final ctx = BanterContext(
      djName: dj.name,
      songTitle: _song.text.trim().isEmpty ? null : _song.text.trim(),
      artist: _artist.text.trim().isEmpty ? null : _artist.text.trim(),
      landmark: _landmark.text.trim().isEmpty ? null : _landmark.text.trim(),
      wildlife: _wildlife.text.trim().isEmpty ? null : _wildlife.text.trim(),
      timeOfDay: _timeOfDay(),
    );
    // Re-roll a few times so "Regenerate" visibly changes when >1 template
    // exists (avoid immediately repeating the last line).
    String? line;
    for (var i = 0; i < 8; i++) {
      line = engine.generate(_station, _situation, ctx);
      if (line == null || line != _output) break;
    }
    setState(() => _output = line ?? 'No template for this combination yet.');
  }

  static String _timeOfDay() {
    final h = DateTime.now().hour;
    if (h < 12) return 'morning';
    if (h < 17) return 'afternoon';
    return 'evening';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roster = ref.watch(djRosterProvider);
    final dj = djForStation(roster, _station);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Banter Generator',
          subtitle:
              'Pick a station and situation, then generate a unique DJ line '
              'from templates + live context. Regenerate for variety.',
        ),
        const Gap.v(AppSpacing.lg),
        AdminSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<DjStation>(
                    initialValue: _station,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Station',
                        isDense: true,
                        border: OutlineInputBorder()),
                    items: [
                      for (final s in DjStation.values)
                        DropdownMenuItem(value: s, child: Text(s.label)),
                    ],
                    onChanged: (s) => setState(() => _station = s ?? _station),
                  ),
                ),
                const Gap.h(AppSpacing.md),
                Expanded(
                  child: DropdownButtonFormField<BanterSituation>(
                    initialValue: _situation,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Situation',
                        isDense: true,
                        border: OutlineInputBorder()),
                    items: [
                      for (final s in BanterSituation.values)
                        DropdownMenuItem(value: s, child: Text(s.label)),
                    ],
                    onChanged: (s) =>
                        setState(() => _situation = s ?? _situation),
                  ),
                ),
              ]),
              const Gap.v(AppSpacing.md),
              Text('Context (optional — fills the template placeholders)',
                  style: theme.textTheme.bodySmall),
              const Gap.v(AppSpacing.sm),
              Row(children: [
                Expanded(child: _f(_song, 'Song title')),
                const Gap.h(AppSpacing.sm),
                Expanded(child: _f(_artist, 'Artist')),
              ]),
              const Gap.v(AppSpacing.sm),
              Row(children: [
                Expanded(child: _f(_landmark, 'Nearby landmark')),
                const Gap.h(AppSpacing.sm),
                Expanded(child: _f(_wildlife, 'Wildlife')),
              ]),
              const Gap.v(AppSpacing.md),
              Row(children: [
                FilledButton.icon(
                  onPressed: _generate,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.lg)),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(_output == null ? 'Generate' : 'Regenerate'),
                ),
                const Gap.h(AppSpacing.md),
                Flexible(
                  child: Text('Host: ${dj.name}'
                      '${dj.voiceName != null ? ' · ${dj.voiceName}' : ''}',
                      style: theme.textTheme.bodySmall),
                ),
              ]),
            ],
          ),
        ),
        if (_output != null) ...[
          const Gap.v(AppSpacing.lg),
          AdminSectionCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.format_quote_rounded, color: theme.colorScheme.primary),
                const Gap.h(AppSpacing.md),
                Expanded(
                  child: Text('"$_output"',
                      style: theme.textTheme.titleMedium?.copyWith(
                          height: 1.4, fontStyle: FontStyle.italic)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _f(TextEditingController c, String label) => TextField(
      controller: c,
      decoration: InputDecoration(
          labelText: label, isDense: true, border: const OutlineInputBorder()));
}

// ── Song Intro Generator ─────────────────────────────────────────────────────

class _SongIntroTab extends ConsumerStatefulWidget {
  const _SongIntroTab();
  @override
  ConsumerState<_SongIntroTab> createState() => _SongIntroTabState();
}

class _SongIntroTabState extends ConsumerState<_SongIntroTab> {
  DjStation _station = DjStation.country;
  final _title = TextEditingController(text: 'Backroad Hymn');
  final _artist = TextEditingController(text: 'The Pines');
  final _theme = TextEditingController(text: "Florida's hidden springs");
  final _park = TextEditingController(text: 'Ocala National Forest');
  final _mood = TextEditingController(text: 'easygoing');
  final _intros = <String>[];

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _theme.dispose();
    _park.dispose();
    _mood.dispose();
    super.dispose();
  }

  void _generate({int count = 1}) {
    final engine = BanterEngine(rng: Random());
    final ctx = BanterContext(
      songTitle: _title.text.trim().isEmpty ? null : _title.text.trim(),
      artist: _artist.text.trim().isEmpty ? null : _artist.text.trim(),
      theme: _theme.text.trim().isEmpty ? null : _theme.text.trim(),
      park: _park.text.trim().isEmpty ? 'Ocala National Forest' : _park.text.trim(),
      mood: _mood.text.trim().isEmpty ? null : _mood.text.trim(),
    );
    setState(() {
      for (var i = 0; i < count; i++) {
        final line = engine.songIntro(_station, ctx);
        if (line != null) _intros.insert(0, line);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Song Intro Generator',
          subtitle:
              'Enter song metadata; generate rotating intros so the same song '
              'almost never sounds the same twice.',
        ),
        const Gap.v(AppSpacing.lg),
        AdminSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<DjStation>(
                initialValue: _station,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Station',
                    isDense: true,
                    border: OutlineInputBorder()),
                items: [
                  for (final s in DjStation.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (s) => setState(() => _station = s ?? _station),
              ),
              const Gap.v(AppSpacing.sm),
              Row(children: [
                Expanded(child: _f(_title, 'Song title')),
                const Gap.h(AppSpacing.sm),
                Expanded(child: _f(_artist, 'Artist')),
              ]),
              const Gap.v(AppSpacing.sm),
              Row(children: [
                Expanded(child: _f(_theme, 'Theme')),
                const Gap.h(AppSpacing.sm),
                Expanded(child: _f(_park, 'Park')),
              ]),
              const Gap.v(AppSpacing.sm),
              _f(_mood, 'Mood'),
              const Gap.v(AppSpacing.md),
              Row(children: [
                FilledButton.icon(
                  onPressed: () => _generate(),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.lg)),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Generate intro'),
                ),
                const Gap.h(AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: () => _generate(count: 10),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.lg)),
                  icon: const Icon(Icons.playlist_add_rounded, size: 18),
                  label: const Text('Generate 10'),
                ),
              ]),
            ],
          ),
        ),
        if (_intros.isNotEmpty) ...[
          const Gap.v(AppSpacing.lg),
          AdminSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_intros.length} generated intro(s)',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Gap.v(AppSpacing.sm),
                for (final line in _intros) ...[
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.play_arrow_rounded, size: 18),
                    const Gap.h(AppSpacing.sm),
                    Expanded(child: Text('"$line"')),
                  ]),
                  const Divider(),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _f(TextEditingController c, String label) => TextField(
      controller: c,
      decoration: InputDecoration(
          labelText: label, isDense: true, border: const OutlineInputBorder()));
}
