import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/around_me/providers/around_me_providers.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/providers/gps_providers.dart';
import 'package:explorer_os_mobile/features/playback/playback_models.dart';
import 'package:explorer_os_mobile/features/radio_director/models/radio_director_models.dart';
import 'package:explorer_os_mobile/features/radio_director/radio_director_controller.dart';

/// A live console for the Radio Director: the four visitor controls, the live
/// decision stream + playback state, quick guide/preferences, and a GPS "drive"
/// simulator so you can watch the Director choose narration vs. music as the
/// vehicle moves through nearby points of interest.
class RadioDirectorDebugPage extends ConsumerStatefulWidget {
  const RadioDirectorDebugPage({super.key});

  @override
  ConsumerState<RadioDirectorDebugPage> createState() =>
      _RadioDirectorDebugPageState();
}

class _RadioDirectorDebugPageState
    extends ConsumerState<RadioDirectorDebugPage> {
  double _lat = 29.1872;
  double _lng = -81.7137;
  Timer? _drive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(aroundMeControllerProvider);
      // Inject self-contained demo audio (production would supply a real
      // playlist + per-POI narration URLs).
      final c = ref.read(radioDirectorControllerProvider.notifier)
        ..musicUrl = _tone(seconds: 30, freq: 196)
        ..narrationFallbackUrl = _tone(seconds: 4, freq: 440);
      c; // keep analyzer happy
      _pushFix();
    });
  }

  @override
  void dispose() {
    _drive?.cancel();
    super.dispose();
  }

  void _pushFix({double speed = 0}) {
    ref.read(gpsServiceProvider).processLocation(GPSLocation(
          latitude: _lat,
          longitude: _lng,
          timestamp: DateTime.now(),
          speedMps: speed,
          accuracyMeters: 5,
        ));
  }

  void _drive0() {
    _drive?.cancel();
    // Head slowly toward the seeded Ocala POI cluster (NE) at walking pace.
    _drive = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _lat += 0.00012;
        _lng += 0.00010;
      });
      _pushFix(speed: 1.4);
    });
    setState(() {});
  }

  void _stopDrive() {
    _drive?.cancel();
    _drive = null;
    _pushFix(speed: 0);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snap = ref.watch(radioDirectorControllerProvider);
    final ctrl = ref.read(radioDirectorControllerProvider.notifier);
    final experiences = ref.watch(aroundMeExperiencesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Radio Director'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Center(
              child: Text(
                snap.conversationOpen
                    ? 'CONVERSATION'
                    : (snap.running ? 'ON AIR' : 'OFF'),
                style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: snap.running
                        ? theme.colorScheme.primary
                        : theme.disabledColor),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _controls(theme, snap, ctrl),
          const Gap.v(AppSpacing.lg),
          _statePanel(theme, snap, experiences.length),
          const Gap.v(AppSpacing.lg),
          _guidePrefs(theme),
          const Gap.v(AppSpacing.lg),
          _simulator(theme),
          const Gap.v(AppSpacing.lg),
          _logPanel(theme, snap),
        ],
      ),
    );
  }

  Widget _controls(
      ThemeData theme, RadioDirectorSnapshot snap, RadioDirectorController c) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: AppRadius.lgAll,
        border:
            Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('The only controls a visitor needs',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const Gap.v(AppSpacing.md),
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => c.togglePlay(),
              icon: Icon(snap.running
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded),
              label: Text(snap.running ? 'Pause' : 'Play'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: snap.running ? () => c.skip() : null,
              icon: const Icon(Icons.skip_next_rounded),
              label: const Text('Skip Narration'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => _conversation(context, c, 'I See Something'),
              icon: const Icon(Icons.visibility_rounded),
              label: const Text('I See Something'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => _conversation(context, c, "What's Around Me"),
              icon: const Icon(Icons.explore_rounded),
              label: const Text("What's Around Me"),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _conversation(
      BuildContext context, RadioDirectorController c, String label) async {
    if (label == 'I See Something') {
      await c.openISeeSomething();
    } else {
      await c.openWhatsAroundMe();
    }
    if (!context.mounted) return;
    final experiences = ref.read(aroundMeExperiencesProvider);
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(label),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label == 'I See Something'
                  ? 'Using your location + nearby wildlife/plants/landmarks, '
                      'the AI guide answers what you\'re looking at. Nearby now:'
                  : 'Here\'s what\'s around you right now:'),
              const Gap.v(AppSpacing.sm),
              if (experiences.isEmpty)
                const Text('— (drive toward the POI cluster first)')
              else
                for (final e in experiences.take(6))
                  Text('• ${e.name}  ·  ${e.category}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close & resume radio'),
          ),
        ],
      ),
    );
    await c.resumeFromConversation();
  }

  Widget _statePanel(ThemeData theme, RadioDirectorSnapshot snap, int nearby) {
    String ch(ChannelStatus s) => s.name;
    final rows = <(String, String)>[
      ('Status', snap.running ? 'On air' : 'Off'),
      ('Last decision', snap.lastDecision?.toString() ?? '—'),
      ('Now narrating', snap.currentNarration ?? '—'),
      ('Music', ch(snap.musicStatus)),
      ('Narration', ch(snap.narrationStatus)),
      ('Since last narration', '${snap.secondsSinceLastNarration.round()}s'),
      ('Played this visit', '${snap.playedCount}'),
      ('Nearby experiences', '$nearby'),
    ];
    return _card(
      theme,
      'Live state',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (k, v) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                    width: 160,
                    child: Text(k,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.disabledColor))),
                Expanded(
                    child: Text(v,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700))),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _guidePrefs(ThemeData theme) {
    final guide = ref.watch(radioGuideProvider);
    final prefs = ref.watch(radioPreferencesProvider);
    return _card(
      theme,
      'Guide & preferences',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const SizedBox(width: 120, child: Text('Guide')),
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
          _slider(theme, 'Music', prefs.musicPercent,
              (v) => ref.read(radioPreferencesProvider.notifier).set(
                  prefs.copyWith(musicPercent: v))),
          _slider(theme, 'Narration', prefs.narrationPercent,
              (v) => ref.read(radioPreferencesProvider.notifier).set(
                  prefs.copyWith(narrationPercent: v))),
          Row(children: [
            const SizedBox(width: 120, child: Text('Story freq')),
            Expanded(
              child: DropdownButton<RadioFrequency>(
                isExpanded: true,
                value: prefs.storyFrequency,
                items: [
                  for (final f in RadioFrequency.values)
                    DropdownMenuItem(value: f, child: Text(f.name)),
                ],
                onChanged: (f) => ref.read(radioPreferencesProvider.notifier)
                    .set(prefs.copyWith(storyFrequency: f)),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _slider(ThemeData theme, String label, int value, ValueChanged<int> on) {
    return Row(children: [
      SizedBox(width: 120, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.toDouble(),
          max: 100,
          divisions: 20,
          label: '$value%',
          onChanged: (v) => on(v.round()),
        ),
      ),
      SizedBox(width: 44, child: Text('$value%', textAlign: TextAlign.end)),
    ]);
  }

  Widget _simulator(ThemeData theme) {
    return _card(
      theme,
      'GPS drive simulator',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Lat ${_lat.toStringAsFixed(5)}, Lng ${_lng.toStringAsFixed(5)}',
              style: theme.textTheme.bodySmall),
          const Gap.v(AppSpacing.sm),
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
              onPressed: () {
                setState(() {
                  _lat = 29.1872;
                  _lng = -81.7137;
                });
                _pushFix();
              },
              icon: const Icon(Icons.my_location_rounded, size: 18),
              label: const Text('Jump to Ocala'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
              onPressed: _drive == null ? _drive0 : null,
              icon: const Icon(Icons.directions_car_rounded, size: 18),
              label: const Text('Drive toward POIs'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
              onPressed: _drive != null ? _stopDrive : null,
              icon: const Icon(Icons.stop_rounded, size: 18),
              label: const Text('Stop'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _logPanel(ThemeData theme, RadioDirectorSnapshot snap) {
    return _card(
      theme,
      'Decision log',
      snap.decisionLog.isEmpty
          ? Text('Press Play, then Drive toward POIs.',
              style: theme.textTheme.bodySmall)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in snap.decisionLog.take(20))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text(line,
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

  /// Compact 8-bit mono WAV sine tone → data URI (self-contained demo audio).
  static String _tone({required double seconds, required double freq}) {
    const rate = 8000;
    final n = (seconds * rate).round();
    final b = Uint8List(44 + n);
    final bd = ByteData.view(b.buffer);
    var p = 0;
    void s(String x) {
      for (final c in x.codeUnits) {
        b[p++] = c;
      }
    }

    void u32(int v) {
      bd.setUint32(p, v, Endian.little);
      p += 4;
    }

    void u16(int v) {
      bd.setUint16(p, v, Endian.little);
      p += 2;
    }

    s('RIFF');
    u32(36 + n);
    s('WAVE');
    s('fmt ');
    u32(16);
    u16(1);
    u16(1);
    u32(rate);
    u32(rate);
    u16(1);
    u16(8);
    s('data');
    u32(n);
    for (var i = 0; i < n; i++) {
      final fade = math.min(1.0, math.min(i, n - i) / 400.0);
      b[44 + i] =
          (128 + 42 * fade * math.sin(2 * math.pi * freq * i / rate)).round().clamp(0, 255);
    }
    return 'data:audio/wav;base64,${base64Encode(b)}';
  }
}
