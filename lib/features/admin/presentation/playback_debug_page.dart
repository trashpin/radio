import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/playback/playback_manager.dart';
import 'package:explorer_os_mobile/features/playback/playback_models.dart';
import 'package:explorer_os_mobile/features/playback/playback_providers.dart';

/// A simple developer panel for exercising the [PlaybackManager] in isolation.
///
/// It drives the engine through its public API and renders a live snapshot
/// (state, current track, queue, priority, volume, channel statuses, last
/// event) — enough to verify queueing, priority interruption, ducking
/// transitions, and error handling by hand. It is NOT wired to GPS, AI,
/// destinations, routes, or Explorer Radio; those connect in later phases.
class PlaybackDebugPage extends ConsumerStatefulWidget {
  const PlaybackDebugPage({super.key});

  @override
  ConsumerState<PlaybackDebugPage> createState() => _PlaybackDebugPageState();
}

class _PlaybackDebugPageState extends ConsumerState<PlaybackDebugPage> {
  // Self-contained generated tones (WAV data URIs) so the panel plays real audio
  // in any browser with no network dependency. Music tracks are long so they can
  // be ducked under a short narration and then resumed.
  late final String _music1 = _toneDataUri(seconds: 30, freq: 196); // low G
  late final String _music2 = _toneDataUri(seconds: 30, freq: 261); // C
  late final String _narrationUrl = _toneDataUri(seconds: 8, freq: 440); // A
  // A deliberately malformed data URI to demonstrate error handling.
  static const _badUrl = 'data:audio/wav;base64,AAAA';

  int _narrationCounter = 0;

  /// Builds a mono 8-bit PCM WAV sine tone and returns it as a `data:` URI.
  static String _toneDataUri({
    required double seconds,
    required double freq,
    int sampleRate = 8000,
    double amplitude = 42,
  }) {
    final n = (seconds * sampleRate).round();
    final bytes = Uint8List(44 + n);
    final bd = ByteData.view(bytes.buffer);
    var p = 0;
    void str(String s) {
      for (final c in s.codeUnits) {
        bytes[p++] = c;
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

    str('RIFF');
    u32(36 + n);
    str('WAVE');
    str('fmt ');
    u32(16);
    u16(1); // PCM
    u16(1); // mono
    u32(sampleRate);
    u32(sampleRate); // byte rate (1 byte/sample, mono)
    u16(1); // block align
    u16(8); // bits per sample
    str('data');
    u32(n);
    for (var i = 0; i < n; i++) {
      // Short fade in/out to avoid clicks.
      final fade = math.min(1.0, math.min(i, n - i) / 400.0);
      final s = 128 + amplitude * fade * math.sin(2 * math.pi * freq * i / sampleRate);
      bytes[44 + i] = s.round().clamp(0, 255);
    }
    return 'data:audio/wav;base64,${base64Encode(bytes)}';
  }

  PlaybackManager get _pm => ref.read(playbackManagerProvider);

  Future<void> _playMusic() => _pm.playMusic(
        PlaybackItem(
          type: PlaybackItemType.music,
          title: 'Sample Song 1',
          audioUrl: _music1,
        ),
        playlist: [
          PlaybackItem(
              type: PlaybackItemType.music,
              title: 'Sample Song 1',
              audioUrl: _music1),
          PlaybackItem(
              type: PlaybackItemType.music,
              title: 'Sample Song 2',
              audioUrl: _music2),
        ],
      );

  Future<void> _sendNarration(PlaybackItemType type, {bool queue = false}) {
    _narrationCounter++;
    final item = PlaybackItem(
      type: type,
      title: '${_titleFor(type)} #$_narrationCounter',
      audioUrl: _narrationUrl,
    );
    return queue ? _pm.queueNarration(item) : _pm.playNarration(item);
  }

  Future<void> _playBadFile() => _pm.playNarration(
        PlaybackItem(
          type: PlaybackItemType.poi,
          title: 'Broken clip',
          audioUrl: _badUrl,
        ),
      );

  String _titleFor(PlaybackItemType t) => switch (t) {
        PlaybackItemType.emergency => 'Emergency',
        PlaybackItemType.safety => 'Safety alert',
        PlaybackItemType.arrival => 'Arrival',
        PlaybackItemType.departure => 'Departure',
        PlaybackItemType.poi => 'POI',
        PlaybackItemType.narration => 'Narration',
        PlaybackItemType.route => 'Route',
        PlaybackItemType.music => 'Music',
      };

  @override
  Widget build(BuildContext context) {
    final snap =
        ref.watch(playbackSnapshotProvider).asData?.value ?? _pm.snapshot;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        Text('Playback Debug',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const Gap.v(AppSpacing.xs),
        Text(
          'Exercises the central PlaybackManager engine directly. '
          'Not connected to GPS / AI / Explorer Radio (Phase 1).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const Gap.v(AppSpacing.lg),
        _StatePanel(snap: snap),
        const Gap.v(AppSpacing.lg),
        _Section(
          title: 'Music',
          children: [
            _btn('Play Music', Icons.play_arrow_rounded, _playMusic),
            _btn('Pause', Icons.pause_rounded, _pm.pauseMusic),
            _btn('Resume', Icons.play_circle_outline_rounded, _pm.resumeMusic),
            _btn('Stop', Icons.stop_rounded, _pm.stopMusic),
            _btn('Previous', Icons.skip_previous_rounded, _pm.previous),
            _btn('Next / Skip', Icons.skip_next_rounded, _pm.next),
            _btn('Crossfade → Song 2', Icons.shuffle_rounded, () {
              return _pm.crossfade(PlaybackItem(
                  type: PlaybackItemType.music,
                  title: 'Sample Song 2',
                  audioUrl: _music2));
            }),
            _btn('Fade Out', Icons.volume_down_rounded, _pm.fadeOut),
            _btn('Fade In', Icons.volume_up_rounded, _pm.fadeIn),
            _btn(snap.muted ? 'Unmute' : 'Mute',
                snap.muted ? Icons.volume_off_rounded : Icons.volume_mute_rounded,
                _pm.toggleMute),
          ],
        ),
        const Gap.v(AppSpacing.md),
        _VolumeRow(volume: snap.volume, onChanged: _pm.setVolume),
        const Gap.v(AppSpacing.lg),
        _Section(
          title: 'Narration & announcements (interrupt music by priority)',
          children: [
            _btn('Play Narration', Icons.record_voice_over_rounded,
                () => _sendNarration(PlaybackItemType.narration)),
            _btn('POI', Icons.place_rounded,
                () => _sendNarration(PlaybackItemType.poi)),
            _btn('Arrival', Icons.flag_rounded,
                () => _sendNarration(PlaybackItemType.arrival)),
            _btn('Safety (90)', Icons.warning_amber_rounded,
                () => _sendNarration(PlaybackItemType.safety)),
            _btn('Emergency (100)', Icons.emergency_rounded,
                () => _sendNarration(PlaybackItemType.emergency)),
            _btn('Queue Narration', Icons.queue_music_rounded,
                () => _sendNarration(PlaybackItemType.narration, queue: true)),
            _btn('Replay', Icons.replay_rounded, _pm.replayNarration),
            _btn('Cancel', Icons.cancel_rounded, _pm.cancelNarration),
            _btn('Clear Queue', Icons.clear_all_rounded, _pm.clearQueue),
            _btn('Play Bad File (error)', Icons.bug_report_rounded, _playBadFile),
          ],
        ),
        const Gap.v(AppSpacing.lg),
        _QueuePanel(queue: snap.queue),
      ],
    );
  }

  Widget _btn(String label, IconData icon, Future<void> Function() onTap) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
      onPressed: () => onTap(),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
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
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const Gap.v(AppSpacing.md),
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: children),
        ],
      ),
    );
  }
}

class _VolumeRow extends StatelessWidget {
  const _VolumeRow({required this.volume, required this.onChanged});

  final double volume;
  final Future<void> Function(double) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.volume_up_rounded, size: 18),
        const Gap.h(AppSpacing.sm),
        Expanded(
          child: Slider(
            value: volume,
            onChanged: (v) => onChanged(v),
          ),
        ),
        SizedBox(
            width: 44,
            child: Text('${(volume * 100).round()}%',
                textAlign: TextAlign.end)),
      ],
    );
  }
}

class _StatePanel extends StatelessWidget {
  const _StatePanel({required this.snap});

  final PlaybackSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <(String, String)>[
      ('Current State', _pretty(snap.state.name)),
      ('Current Track', snap.currentTrack?.title ?? '—'),
      ('Queue Length', '${snap.queueLength}'),
      ('Current Priority', snap.currentPriority?.toString() ?? '—'),
      ('Current Volume', '${(snap.volume * 100).round()}%'
          '${snap.muted ? ' (muted)' : ''}'),
      ('Music Status', _pretty(snap.musicStatus.name)),
      ('Narration Status', _pretty(snap.narrationStatus.name)),
      ('Last Event', snap.lastEvent?.toString() ?? '—'),
    ];
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
          for (final (k, v) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(k,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.disabledColor)),
                  ),
                  Expanded(
                    child: Text(v,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _pretty(String enumName) {
    final out = StringBuffer();
    for (var i = 0; i < enumName.length; i++) {
      final c = enumName[i];
      if (i > 0 && c.toUpperCase() == c && c.toLowerCase() != c) {
        out.write(' ');
      }
      out.write(i == 0 ? c.toUpperCase() : c);
    }
    return out.toString();
  }
}

class _QueuePanel extends StatelessWidget {
  const _QueuePanel({required this.queue});

  final List<PlaybackItem> queue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
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
          Text('Queue (${queue.length})',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const Gap.v(AppSpacing.sm),
          if (queue.isEmpty)
            Text('Empty', style: theme.textTheme.bodySmall)
          else
            for (final item in queue)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: AppRadius.smAll,
                      ),
                      child: Text('p${item.priority}',
                          style: theme.textTheme.labelSmall),
                    ),
                    const Gap.h(AppSpacing.sm),
                    Expanded(child: Text(item.title)),
                    Text(item.type.name, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
