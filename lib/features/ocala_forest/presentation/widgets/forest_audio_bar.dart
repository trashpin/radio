import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'package:explorer_os_mobile/features/ocala_forest/controllers/forest_audio_controller.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// 🌲 FOREST AUDIO — a small, clearly-labeled now-playing bar so the
/// visitor can immediately tell they're hearing forest information, not
/// the radio (spec §5). Shows itself only while [ForestAudioController]
/// has something loaded; otherwise renders nothing. Embed this in any
/// screen that can trigger forest narration (Discoveries, Around Me,
/// Forest Stories, Trail Stops).
class ForestAudioBar extends ConsumerWidget {
  const ForestAudioBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioState = ref.watch(forestAudioControllerProvider);
    if (!audioState.isActive) return const SizedBox.shrink();

    final controller = ref.read(forestAudioControllerProvider.notifier);

    return GlassPanel(
      child: Row(
        children: [
          const Icon(Icons.park_rounded, color: RD.green),
          const SizedBox(width: RD.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('🌲 FOREST AUDIO', style: RD.caption.copyWith(color: RD.green)),
                Text(
                  audioState.title ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RD.cardTitle.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
          if (controller.usingTts)
            IconButton(
              onPressed: audioState.isSpeaking ? controller.pause : controller.resume,
              icon: Icon(
                audioState.isSpeaking ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
              ),
            )
          else
            StreamBuilder<PlayerState>(
              stream: controller.player.playerStateStream,
              builder: (context, snapshot) {
                final playing = snapshot.data?.playing ?? false;
                return IconButton(
                  onPressed: playing ? controller.pause : controller.resume,
                  icon: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                  ),
                );
              },
            ),
          IconButton(
            onPressed: controller.replay,
            icon: const Icon(Icons.replay_rounded, color: Colors.white),
            tooltip: 'Replay',
          ),
        ],
      ),
    );
  }
}
