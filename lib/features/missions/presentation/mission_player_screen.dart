import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/features/missions/controllers/active_mission_controller.dart';
import 'package:explorer_os_mobile/features/missions/controllers/mission_audio_controller.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_repository.dart';
import 'package:explorer_os_mobile/features/missions/presentation/journey_map.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// The primary in-mission player (spec Phase 7, refined with a real
/// Journey Map): audio-first, deliberately sparse — the player should
/// always know where they are, where they're going, and what's happening,
/// without staring at the screen while driving. The map is visual support
/// for the audio-first experience, not the other way around — see
/// [JourneyMap]'s own doc comment for what it reuses.
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
                        const SizedBox(height: RD.md),
                        const SizedBox(height: 280, child: JourneyMap()),
                        const SizedBox(height: RD.md),
                        Expanded(child: _NowPlayingCard(
                          narrationText: state.lastNarrationText,
                          isSpeaking: audio.isActive,
                          awaitingQr: state.awaitingQr,
                        )),
                        const SizedBox(height: RD.md),
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

/// "What am I looking for? What's happening now?" — the main focal point
/// for audio/story state. Distance/proximity now lives on the Journey Map
/// above (one place for that number, not two) — this card stays focused on
/// the story itself.
class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({
    required this.narrationText,
    required this.isSpeaking,
    required this.awaitingQr,
  });
  final String? narrationText;
  final bool isSpeaking;
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
              size: 48,
              color: RD.green,
            ),
            const SizedBox(height: RD.md),
            Text(
              awaitingQr
                  ? "You've arrived. Look around for the QR marker."
                  : (narrationText ?? 'Drive on — the story continues as you travel.'),
              textAlign: TextAlign.center,
              style: RD.body.copyWith(fontSize: 15, color: RD.textPrimary),
            ),
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
