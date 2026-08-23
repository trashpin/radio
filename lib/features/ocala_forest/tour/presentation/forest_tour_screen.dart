import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'package:explorer_os_mobile/features/ocala_forest/controllers/forest_audio_controller.dart';
import 'package:explorer_os_mobile/features/ocala_forest/tour/controllers/forest_tour_controller.dart';
import 'package:explorer_os_mobile/features/ocala_forest/tour/models/tour_story_type.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// 🎧 TAKE ME ON A TOUR (spec §1/§18) — deliberately sparse: the visitor
/// should be listening, not staring at the phone. One primary action to
/// start, then a small, fixed set of controls once it's running.
class ForestTourScreen extends ConsumerStatefulWidget {
  const ForestTourScreen({super.key});

  @override
  ConsumerState<ForestTourScreen> createState() => _ForestTourScreenState();
}

class _ForestTourScreenState extends ConsumerState<ForestTourScreen> {
  @override
  void dispose() {
    // Leaving the tour screen ends the tour (and, via ForestAudioController,
    // restores the radio to whatever it was doing before — spec §15).
    if (ref.read(forestTourControllerProvider).isActive) {
      ref.read(forestTourControllerProvider.notifier).endTour();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tour = ref.watch(forestTourControllerProvider);

    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Column(
          children: [
            const RadioSubPageBar(title: '🌲 Ocala Forest Tour', subtitle: 'Ocala National Forest'),
            Expanded(
              child: tour.status == TourStatus.idle
                  ? _StartCard(
                      error: tour.error,
                      onStart: () => ref.read(forestTourControllerProvider.notifier).startTour(),
                    )
                  : tour.status == TourStatus.ended
                      ? _EndedCard(
                          onRestart: () =>
                              ref.read(forestTourControllerProvider.notifier).startTour(),
                        )
                      : _ActiveTour(state: tour),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartCard extends StatelessWidget {
  const _StartCard({required this.onStart, this.error});
  final VoidCallback onStart;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RD.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.headphones_rounded, size: 64, color: RD.green),
            const SizedBox(height: RD.lg),
            Text(
              'Press the button and I\'ll be your guide as you explore Ocala National Forest.',
              textAlign: TextAlign.center,
              style: RD.title.copyWith(color: Colors.white),
            ),
            if (error != null) ...[
              const SizedBox(height: RD.md),
              Text(error!, textAlign: TextAlign.center, style: RD.body.copyWith(color: RD.live)),
            ],
            const SizedBox(height: RD.xl),
            ElevatedButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.headphones_rounded),
              label: const Text('🎧 TAKE ME ON A TOUR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: RD.green,
                foregroundColor: RD.onGreen,
                minimumSize: const Size(double.infinity, 56),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EndedCard extends StatelessWidget {
  const _EndedCard({required this.onRestart});
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RD.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.forest_rounded, size: 56, color: RD.textSecondary),
            const SizedBox(height: RD.lg),
            Text('Tour ended. Thanks for exploring!',
                textAlign: TextAlign.center, style: RD.title.copyWith(color: Colors.white)),
            const SizedBox(height: RD.xl),
            OutlinedButton(
              onPressed: onRestart,
              style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
              child: const Text('START A NEW TOUR', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveTour extends ConsumerWidget {
  const _ActiveTour({required this.state});
  final ForestTourState state;

  String _storyBadge(TourStoryType t) {
    switch (t) {
      case TourStoryType.folklore:
        return '🌙 FOLKLORE';
      case TourStoryType.legend:
        return '🌙 LEGEND';
      case TourStoryType.unverified:
        return '❓ UNVERIFIED';
      case TourStoryType.verifiedHistory:
        return '📜 VERIFIED HISTORY';
      case TourStoryType.wildlife:
        return '🐾 WILDLIFE';
      case TourStoryType.nature:
        return '🌿 NATURE';
      case TourStoryType.geology:
        return '🪨 GEOLOGY';
      case TourStoryType.localStory:
        return '📖 LOCAL STORY';
      case TourStoryType.general:
        return '🌲 FOREST';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(forestTourControllerProvider.notifier);
    final audioState = ref.watch(forestAudioControllerProvider);
    final audioController = ref.read(forestAudioControllerProvider.notifier);

    // spec §9: "Finding your location…" / "Finding stories near you…" —
    // shown only before the first real segment exists.
    if (state.statusMessage != null && state.currentText == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(RD.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: RD.lg),
              Text(state.statusMessage!,
                  textAlign: TextAlign.center, style: RD.title.copyWith(color: Colors.white)),
              if (state.error != null) ...[
                const SizedBox(height: RD.lg),
                Text(state.error!, textAlign: TextAlign.center, style: RD.body.copyWith(color: RD.live)),
              ],
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(RD.lg),
      children: [
        if (state.gpsWarning != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(RD.sm),
            decoration: BoxDecoration(
              color: RD.amber.withValues(alpha: 0.14),
              borderRadius: RD.brMd,
            ),
            child: Text('📶 ${state.gpsWarning!}',
                textAlign: TextAlign.center, style: RD.caption.copyWith(color: RD.amber)),
          ),
          const SizedBox(height: RD.sm),
        ],
        Text("You're here:", style: RD.caption.copyWith(color: RD.textSecondary)),
        Text(state.currentSubjectName ?? 'Ocala National Forest',
            style: RD.title.copyWith(color: Colors.white)),
        const SizedBox(height: RD.lg),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('🎙️ NOW PLAYING', style: RD.sectionLabel),
                  const Spacer(),
                  if (state.currentText != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: RD.sm, vertical: 2),
                      decoration: BoxDecoration(
                        color: state.currentStoryType.isUnverified
                            ? RD.amber.withValues(alpha: 0.18)
                            : RD.green.withValues(alpha: 0.14),
                        borderRadius: RD.brMd,
                      ),
                      child: Text(
                        _storyBadge(state.currentStoryType),
                        style: RD.caption.copyWith(
                          color: state.currentStoryType.isUnverified ? RD.amber : RD.green,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: RD.sm),
              if (state.loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: RD.lg),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Text(state.currentText ?? '', style: RD.body.copyWith(color: Colors.white)),
            ],
          ),
        ),
        if (state.error != null) ...[
          const SizedBox(height: RD.sm),
          Text(state.error!, style: RD.body.copyWith(color: RD.live)),
        ],
        const SizedBox(height: RD.lg),
        Center(
          child: audioController.usingTts
              ? IconButton(
                  iconSize: 56,
                  color: RD.green,
                  onPressed: audioState.isSpeaking ? controller.pause : controller.resume,
                  icon: Icon(audioState.isSpeaking ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
                )
              : StreamBuilder<PlayerState>(
                  stream: audioController.player.playerStateStream,
                  builder: (context, snapshot) {
                    final playing = snapshot.data?.playing ?? false;
                    return IconButton(
                      iconSize: 56,
                      color: RD.green,
                      onPressed: playing ? controller.pause : controller.resume,
                      icon: Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
                    );
                  },
                ),
        ),
        const SizedBox(height: RD.lg),
        OutlinedButton.icon(
          onPressed: state.loading ? null : controller.tellMeSomething,
          icon: const Icon(Icons.mic_rounded, color: Colors.white),
          label: const Text('🎙️ TELL ME SOMETHING', style: TextStyle(color: Colors.white)),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
        ),
        const SizedBox(height: RD.sm),
        OutlinedButton.icon(
          onPressed: state.loading ? null : controller.nextStory,
          icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
          label: const Text('⏭ NEXT STORY', style: TextStyle(color: Colors.white)),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
        ),
        const SizedBox(height: RD.sm),
        OutlinedButton.icon(
          onPressed: controller.replay,
          icon: const Icon(Icons.replay_rounded, color: Colors.white),
          label: const Text('🔄 REPLAY', style: TextStyle(color: Colors.white)),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
        ),
        const SizedBox(height: RD.lg),
        OutlinedButton(
          onPressed: () {
            controller.endTour();
            Navigator.of(context).maybePop();
          },
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
            side: const BorderSide(color: RD.live),
          ),
          child: const Text('🛑 END TOUR', style: TextStyle(color: RD.live)),
        ),
      ],
    );
  }
}
