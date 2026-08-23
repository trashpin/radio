import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'package:explorer_os_mobile/features/ocala_forest/models/forest_trail.dart';
import 'package:explorer_os_mobile/features/ocala_forest/presentation/forest_trail_map_image_screen.dart';
import 'package:explorer_os_mobile/features/ocala_forest/presentation/forest_trail_map_screen.dart';
import 'package:explorer_os_mobile/features/ocala_forest/services/forest_trail_audio_service.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// The dedicated trail page (spec §1/§12): official trail information, the
/// actual trail map (an official image if one is ever attached, else the
/// real imported USFS geometry — never a hand-drawn approximation), and
/// the ElevenLabs Trail Audio Tour. The two primary actions (VIEW TRAIL
/// MAP / START TRAIL AUDIO) are always visible near the top, never buried
/// in a menu.
///
/// GPS-triggered audio stops are explicitly OUT of scope for this phase
/// (spec §9) — this screen only plays a single trail-wide introduction,
/// started manually before the visitor begins walking. The existing GPS/
/// geofencing systems are untouched; nothing here listens to them.
class ForestTrailDetailScreen extends ConsumerStatefulWidget {
  const ForestTrailDetailScreen({super.key, required this.trail});
  final ForestTrail trail;

  @override
  ConsumerState<ForestTrailDetailScreen> createState() => _ForestTrailDetailScreenState();
}

class _ForestTrailDetailScreenState extends ConsumerState<ForestTrailDetailScreen> {
  late ForestTrail _trail = widget.trail;
  final _player = AudioPlayer();
  bool _preparingAudio = false;
  String? _audioError;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _startTrailAudio() async {
    setState(() => _audioError = null);
    if (_trail.hasReadyAudio) {
      await _playLoaded(_trail.audioUrl!);
      return;
    }
    setState(() => _preparingAudio = true);
    final result = await ref.read(forestTrailAudioServiceProvider).ensureAudio(_trail.id);
    if (!mounted) return;
    setState(() => _preparingAudio = false);
    if (result == null) {
      setState(() => _audioError = "Couldn't prepare the audio tour — check your connection and try again.");
      return;
    }
    setState(() {
      _trail = _trail.copyWithAudio(
        audioUrl: result.audioUrl,
        audioScript: result.script,
        audioDurationSeconds: result.durationSeconds,
        audioStatus: 'ready',
      );
    });
    await _playLoaded(result.audioUrl);
  }

  Future<void> _playLoaded(String url) async {
    try {
      if (_player.audioSource == null) {
        await _player.setUrl(url);
      }
      await _player.play();
    } catch (e) {
      if (mounted) setState(() => _audioError = 'Could not play the audio tour: $e');
    }
  }

  Future<void> _pause() => _player.pause();

  Future<void> _restart() async {
    await _player.seek(Duration.zero);
    await _player.play();
  }

  @override
  Widget build(BuildContext context) {
    final t = _trail;
    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Column(
          children: [
            RadioSubPageBar(
              title: (t.trailName?.trim().isNotEmpty ?? false) ? t.trailName! : 'Trail ${t.trailNo}',
              subtitle: 'Ocala National Forest',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(RD.lg),
                children: [
                  // The two primary, mobile-first actions — always visible,
                  // never behind a menu (spec §12).
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => t.hasOfficialMap
                          ? ForestTrailMapImageScreen(trail: t)
                          : ForestTrailMapScreen(trail: t),
                    )),
                    icon: const Icon(Icons.map_rounded),
                    label: const Text('🗺️ VIEW TRAIL MAP'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: RD.green,
                      foregroundColor: RD.onGreen,
                      minimumSize: const Size(double.infinity, 56),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: RD.md),
                  _TrailInfoCard(trail: t),
                  const SizedBox(height: RD.lg),
                  _TrailAudioSection(
                    trail: t,
                    player: _player,
                    preparing: _preparingAudio,
                    error: _audioError,
                    onStart: _startTrailAudio,
                    onPause: _pause,
                    onRestart: _restart,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrailInfoCard extends StatelessWidget {
  const _TrailInfoCard({required this.trail});
  final ForestTrail trail;

  @override
  Widget build(BuildContext context) {
    final rows = <MapEntry<String, String>>[
      MapEntry('Official trail number', trail.trailNo),
      if (trail.lengthMiles != null)
        MapEntry('Length', '${trail.lengthMiles!.toStringAsFixed(1)} miles'),
      if (trail.trailType != null && trail.trailType!.trim().isNotEmpty)
        MapEntry('Trail type/use', trail.trailType!),
      if (trail.trailSurface != null && trail.trailSurface!.trim().isNotEmpty)
        MapEntry('Surface', trail.trailSurface!),
      if (trail.trailClass != null && trail.trailClass!.trim().isNotEmpty)
        MapEntry('Trail class', trail.trailClass!),
      if (trail.accessibilityStatus != null && trail.accessibilityStatus!.trim().isNotEmpty)
        MapEntry('Accessibility', trail.accessibilityStatus!),
      if (trail.nationalTrailDesignation == 3)
        const MapEntry('National designation', 'Florida National Scenic Trail'),
      if (trail.segmentCount > 0)
        MapEntry('Mapped segments', '${trail.segmentCount}'),
    ];

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Trail Information', style: RD.sectionLabel),
          const SizedBox(height: RD.sm),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: RD.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(r.key, style: RD.caption.copyWith(color: RD.textSecondary)),
                  ),
                  Expanded(
                    child: Text(r.value, style: RD.body.copyWith(color: Colors.white)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: RD.xs),
          Text(
            'Source: ${trail.source ?? 'U.S. Forest Service'}'
            '${trail.sourceDataset != null ? ' — ${trail.sourceDataset}' : ''}',
            style: RD.caption.copyWith(color: RD.textFaint),
          ),
        ],
      ),
    );
  }
}

class _TrailAudioSection extends StatelessWidget {
  const _TrailAudioSection({
    required this.trail,
    required this.player,
    required this.preparing,
    required this.error,
    required this.onStart,
    required this.onPause,
    required this.onRestart,
  });

  final ForestTrail trail;
  final AudioPlayer player;
  final bool preparing;
  final String? error;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onRestart;

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🎙️ TRAIL AUDIO TOUR', style: RD.sectionLabel),
          const SizedBox(height: RD.sm),
          Text(
            'A quick spoken introduction before you start walking.',
            style: RD.body.copyWith(color: RD.textSecondary),
          ),
          const SizedBox(height: RD.md),
          StreamBuilder<PlayerState>(
            stream: player.playerStateStream,
            builder: (context, snapshot) {
              final playing = snapshot.data?.playing ?? false;
              return Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: preparing ? null : (playing ? onPause : onStart),
                      icon: preparing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                      label: Text(preparing
                          ? 'PREPARING…'
                          : playing
                              ? 'PAUSE'
                              : '▶ START TRAIL AUDIO'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: RD.green,
                        foregroundColor: RD.onGreen,
                        minimumSize: const Size(0, 52),
                      ),
                    ),
                  ),
                  const SizedBox(width: RD.sm),
                  OutlinedButton(
                    onPressed: preparing ? null : onRestart,
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                    child: const Icon(Icons.replay_rounded, color: Colors.white),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: RD.sm),
          StreamBuilder<Duration?>(
            stream: player.durationStream,
            builder: (context, durationSnap) {
              final duration = durationSnap.data ?? const Duration();
              return StreamBuilder<Duration>(
                stream: player.positionStream,
                builder: (context, positionSnap) {
                  final position = positionSnap.data ?? Duration.zero;
                  final total = duration.inMilliseconds > 0
                      ? duration
                      : Duration(
                          seconds: (trail.audioDurationSeconds ?? 0).round(),
                        );
                  final progress = total.inMilliseconds > 0
                      ? (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
                      : 0.0;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(
                        value: progress,
                        backgroundColor: RD.panelAlt,
                        color: RD.green,
                      ),
                      const SizedBox(height: RD.xs),
                      Text(
                        '${_fmt(position)} / ${_fmt(total)}',
                        style: RD.caption.copyWith(color: RD.textSecondary),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          if (error != null) ...[
            const SizedBox(height: RD.sm),
            Text(error!, style: RD.body.copyWith(color: RD.live)),
          ],
        ],
      ),
    );
  }
}
