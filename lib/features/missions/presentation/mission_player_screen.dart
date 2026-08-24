import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/features/missions/controllers/active_mission_controller.dart';
import 'package:explorer_os_mobile/features/missions/controllers/mission_audio_controller.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_repository.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

const double _mile = 1609.344;
const double _foot = 0.3048;

/// "500 feet" / "2.3 mi" — friendly, rounded, never claims false precision.
String _friendlyDistance(double meters) {
  final miles = meters / _mile;
  if (miles >= 0.25) return '${miles.toStringAsFixed(1)} mi';
  final feet = (meters / _foot).round();
  return '$feet ft';
}

/// The primary in-mission player (spec Phase 7): audio-first, deliberately
/// sparse — the player should always know where they are, what they're
/// doing, what they're looking for, and what happens next, without staring
/// at the screen while driving. Reuses the exact same audio-first, minimal-
/// chrome philosophy already established by RadioScreen/DiscoverHomeScreen.
class MissionPlayerScreen extends ConsumerStatefulWidget {
  const MissionPlayerScreen({super.key, required this.missionId});
  final String missionId;

  @override
  ConsumerState<MissionPlayerScreen> createState() => _MissionPlayerScreenState();
}

class _MissionPlayerScreenState extends ConsumerState<MissionPlayerScreen> {
  bool _started = false;

  @override
  Widget build(BuildContext context) {
    final missionAsync = ref.watch(missionByIdProvider(widget.missionId));
    final state = ref.watch(activeMissionControllerProvider);
    final audio = ref.watch(missionAudioControllerProvider);

    return missionAsync.when(
      loading: () => const Scaffold(
        backgroundColor: RD.bg,
        body: Center(child: CircularProgressIndicator(color: RD.green)),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: RD.bg,
        body: Center(child: Text('Could not load this adventure.', style: RD.body)),
      ),
      data: (mission) {
        if (mission == null) {
          return Scaffold(
            backgroundColor: RD.bg,
            body: Center(child: Text('Adventure not found.', style: RD.body)),
          );
        }

        if (!_started) {
          _started = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(activeMissionControllerProvider.notifier).startMission(mission);
          });
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // A stop with requiresQr=false can reach mission-complete or a
          // pending final puzzle directly from a GPS arrival, with no QR
          // scan screen in between to make this transition from — this
          // player screen is the one place both paths always pass through.
          if (state.hasPendingPuzzle) {
            context.pushReplacement(AppRoute.missionPuzzle.path);
          } else if (state.missionComplete) {
            context.pushReplacement(AppRoute.missionComplete.path);
          }
        });

        return Scaffold(
          backgroundColor: RD.bg,
          appBar: AppBar(
            backgroundColor: RD.bg,
            foregroundColor: RD.textPrimary,
            title: Text(mission.title, overflow: TextOverflow.ellipsis),
          ),
          body: SafeArea(
            child: state.loading || state.currentStop == null
                ? const Center(child: CircularProgressIndicator(color: RD.green))
                : Padding(
                    padding: const EdgeInsets.all(RD.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _WhereAmI(stopTitle: state.currentStop!.title, xp: state.xp),
                        const SizedBox(height: RD.lg),
                        Expanded(child: _NowPlayingCard(
                          narrationText: state.lastNarrationText,
                          isSpeaking: audio.isActive,
                          distanceMeters: state.lastDistanceMeters,
                          awaitingQr: state.awaitingQr,
                        )),
                        const SizedBox(height: RD.lg),
                        if (state.awaitingQr)
                          _FindQrButton(missionId: mission.id)
                        else
                          _StatusFooter(distanceMeters: state.lastDistanceMeters),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }
}

/// "Where am I? What am I doing?" — always visible at the top.
class _WhereAmI extends StatelessWidget {
  const _WhereAmI({required this.stopTitle, required this.xp});
  final String stopTitle;
  final int xp;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('HEADING TO', style: RD.sectionLabel),
            const SizedBox(height: 2),
            Text(stopTitle, style: RD.title),
          ],
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: RD.md, vertical: RD.xs),
        decoration: BoxDecoration(
          color: RD.panelAlt,
          borderRadius: BorderRadius.circular(RD.rPill),
        ),
        child: Text('$xp XP', style: RD.caption.copyWith(color: RD.green)),
      ),
    ]);
  }
}

/// "What am I looking for? What's happening now?" — the main focal point.
/// Audio is the primary experience; this card just reflects what's already
/// playing rather than asking the player to read anything long.
class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({
    required this.narrationText,
    required this.isSpeaking,
    required this.distanceMeters,
    required this.awaitingQr,
  });
  final String? narrationText;
  final bool isSpeaking;
  final double? distanceMeters;
  final bool awaitingQr;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(RD.xl),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              awaitingQr
                  ? Icons.qr_code_scanner_rounded
                  : (isSpeaking ? Icons.graphic_eq_rounded : Icons.explore_rounded),
              size: 64,
              color: RD.green,
            ),
            const SizedBox(height: RD.lg),
            Text(
              awaitingQr
                  ? "You've arrived. Look around for the QR marker."
                  : (narrationText ?? 'Drive on — the story continues as you travel.'),
              textAlign: TextAlign.center,
              style: RD.body.copyWith(fontSize: 15, color: RD.textPrimary),
            ),
            if (!awaitingQr && distanceMeters != null) ...[
              const SizedBox(height: RD.lg),
              Text(_friendlyDistance(distanceMeters!), style: RD.wordmark.copyWith(fontSize: 22)),
              Text('to go', style: RD.caption),
            ],
          ],
        ),
      ),
    );
  }
}

class _FindQrButton extends ConsumerWidget {
  const _FindQrButton({required this.missionId});
  final String missionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 56,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: RD.green, foregroundColor: RD.onGreen),
        onPressed: () => context.push(AppRoute.qrScan.path),
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: const Text('Scan QR Marker', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _StatusFooter extends StatelessWidget {
  const _StatusFooter({required this.distanceMeters});
  final double? distanceMeters;

  @override
  Widget build(BuildContext context) {
    return Text(
      distanceMeters == null
          ? 'Waiting for GPS…'
          : 'Keep driving — the story will continue automatically.',
      textAlign: TextAlign.center,
      style: RD.caption,
    );
  }
}
