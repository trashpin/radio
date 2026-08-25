import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/missions/controllers/mission_audio_controller.dart';
import 'package:explorer_os_mobile/features/missions/data/treasure_map_provider.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_map_piece.dart';
import 'package:explorer_os_mobile/features/missions/presentation/widgets/character_video_hero.dart';
import 'package:explorer_os_mobile/features/missions/services/safe_travel.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// THE SECOND LAYER — "what have I discovered?", alongside (never instead
/// of) the existing navigation map's "where do I go?". Opened from a
/// button on [MissionPlayerScreen]; everything here is read-only
/// aggregation via [treasureMapProvider] — nothing on this screen ever
/// touches GPS, geofencing, or `ActiveMissionController`.
class TreasureMapPanelScreen extends ConsumerWidget {
  const TreasureMapPanelScreen({super.key, required this.missionId});
  final String missionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(treasureMapProvider(missionId));
    return Scaffold(
      backgroundColor: RD.bg,
      appBar: AppBar(
        backgroundColor: RD.bg,
        foregroundColor: RD.textPrimary,
        title: const Text('Treasure Map & Clues'),
      ),
      body: SafeArea(
        child: dataAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: RD.amber)),
          error: (e, _) => Center(child: Text('Could not load your discoveries.', style: RD.body)),
          data: (data) => ListView(
            padding: const EdgeInsets.all(RD.lg),
            children: [
              Text('YOUR MAP', style: RD.tagline.copyWith(color: RD.amber, letterSpacing: 3)),
              const SizedBox(height: RD.xs),
              Text('MAP PIECES  ${data.foundCount} / ${data.totalCount} FOUND',
                  style: RD.sectionLabel.copyWith(color: Colors.white70)),
              const SizedBox(height: RD.md),
              if (data.pieces.isEmpty)
                Text('No map pieces configured for this adventure yet.',
                    style: RD.caption.copyWith(color: RD.textSecondary))
              else
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: RD.sm,
                  crossAxisSpacing: RD.sm,
                  children: [for (final p in data.pieces) _MapPieceTile(status: p)],
                ),
              const SizedBox(height: RD.xxl),
              Text('CLUES FOUND', style: RD.tagline.copyWith(color: RD.amber, letterSpacing: 3)),
              const SizedBox(height: RD.md),
              if (data.clues.isEmpty)
                Text('Nothing discovered yet — keep exploring.',
                    style: RD.caption.copyWith(color: RD.textSecondary))
              else
                for (final clue in data.clues) _ClueRow(clue: clue),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapPieceTile extends StatelessWidget {
  const _MapPieceTile({required this.status});
  final MapPieceStatus status;

  @override
  Widget build(BuildContext context) {
    final url = status.imageUrlIfFound;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: ClipRRect(
        key: ValueKey(status.found),
        borderRadius: RD.brMd,
        child: status.found
            ? ((url ?? '').isNotEmpty
                ? Image.network(url!, fit: BoxFit.cover)
                : Container(color: RD.green.withValues(alpha: 0.25),
                    child: const Icon(Icons.check_rounded, color: RD.green)))
            : Container(
                color: RD.panelAlt,
                child: const Center(child: Icon(Icons.lock_outline_rounded, color: RD.textSecondary)),
              ),
      ),
    );
  }
}

class _ClueRow extends ConsumerWidget {
  const _ClueRow({required this.clue});
  final FoundClue clue;

  IconData get _icon => switch (clue.clueType) {
        kClueTypeImage => Icons.image_outlined,
        kClueTypeAudio => Icons.graphic_eq_rounded,
        kClueTypeVideo => Icons.videocam_outlined,
        kClueTypeRiddle => Icons.psychology_alt_rounded,
        kClueTypeMapFragment => Icons.map_outlined,
        kClueTypeCharacterMessage => Icons.person_outline_rounded,
        _ => Icons.description_outlined,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: RD.sm),
      child: GlassPanel(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => ClueViewerSheet(clue: clue),
        ),
        child: Row(children: [
          Icon(_icon, color: RD.amber, size: 20),
          const SizedBox(width: RD.md),
          Expanded(
            child: Text(clue.title, style: RD.body.copyWith(color: Colors.white, fontSize: 14)),
          ),
          const Icon(Icons.chevron_right_rounded, color: RD.textSecondary),
        ]),
      ),
    );
  }
}

/// The type-specific viewer for one already-found clue. The safe-travel
/// gate lives here, not on the list — the player can always see WHAT
/// they've found while driving, just not interact with a visual clue
/// until they're safely stopped (audio is never gated). Public because
/// `GuideHomeScreen`'s "AVAILABLE CLUES" quick-access chips reuse it
/// directly rather than re-implementing clue playback a second time.
class ClueViewerSheet extends ConsumerWidget {
  const ClueViewerSheet({super.key, required this.clue});
  final FoundClue clue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(gpsControllerProvider).location?.speedMps;
    final moving = isMovingTooFastForInteraction(speed);
    final needsSafeStop = clue.clueType != kClueTypeAudio;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: RD.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(RD.rLg)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(RD.lg),
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: RD.panelAlt, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: RD.lg),
            if (clue.characterName != null) ...[
              Row(children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: RD.panelAlt,
                  backgroundImage: (clue.characterImageUrl ?? '').isNotEmpty
                      ? NetworkImage(clue.characterImageUrl!)
                      : null,
                  child: (clue.characterImageUrl ?? '').isEmpty
                      ? const Icon(Icons.person_rounded, color: RD.textSecondary)
                      : null,
                ),
                const SizedBox(width: RD.md),
                Text(clue.characterName!, style: RD.cardTitle.copyWith(color: Colors.white)),
              ]),
              const SizedBox(height: RD.lg),
            ],
            Text(clue.title, style: RD.wordmark.copyWith(fontSize: 20, color: Colors.white)),
            const SizedBox(height: RD.lg),
            if ((clue.audioUrl ?? '').isNotEmpty) _AudioClueControls(clue: clue),
            if (needsSafeStop && moving) ...[
              const SizedBox(height: RD.lg),
              GlassPanel(
                color: RD.amber.withValues(alpha: 0.12),
                child: Row(children: [
                  const Icon(Icons.directions_car_filled_rounded, color: RD.amber),
                  const SizedBox(width: RD.sm),
                  Expanded(
                    child: Text("A new clue is waiting for you at your next safe stop.",
                        style: RD.body.copyWith(color: Colors.white)),
                  ),
                ]),
              ),
            ] else ...[
              const SizedBox(height: RD.lg),
              ..._buildContent(),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildContent() {
    switch (clue.clueType) {
      case kClueTypeImage:
      case kClueTypeMapFragment:
        return [
          if ((clue.text ?? '').isNotEmpty) ...[
            Text('LOOK CLOSELY', style: RD.sectionLabel.copyWith(color: RD.amber)),
            const SizedBox(height: RD.xs),
            Text(clue.text!, style: RD.body.copyWith(color: Colors.white, fontStyle: FontStyle.italic)),
            const SizedBox(height: RD.md),
          ],
          if ((clue.imageUrl ?? '').isNotEmpty)
            ClipRRect(
              borderRadius: RD.brLg,
              child: InteractiveViewer(
                maxScale: 4,
                child: Image.network(clue.imageUrl!, fit: BoxFit.contain),
              ),
            ),
        ];
      case kClueTypeVideo:
      case kClueTypeCharacterMessage:
        return [
          if ((clue.videoUrl ?? '').isNotEmpty)
            CharacterVideoHero(videoUrl: clue.videoUrl!)
          else if ((clue.text ?? '').isNotEmpty)
            Text(clue.text!, style: RD.body.copyWith(color: Colors.white, fontSize: 15, height: 1.5)),
        ];
      case kClueTypeRiddle:
      case kClueTypeText:
      default:
        return [
          if ((clue.text ?? '').isNotEmpty)
            Text(clue.text!, style: RD.body.copyWith(color: Colors.white, fontSize: 16, height: 1.6)),
        ];
    }
  }
}

class _AudioClueControls extends ConsumerWidget {
  const _AudioClueControls({required this.clue});
  final FoundClue clue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioState = ref.watch(missionAudioControllerProvider);
    final playing = audioState.isActive && audioState.title == clue.title;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: RD.amber, foregroundColor: Colors.black),
            onPressed: () {
              final controller = ref.read(missionAudioControllerProvider.notifier);
              if (playing) {
                controller.replay(clue.title);
              } else {
                controller.play(title: clue.title, audioUrl: clue.audioUrl, spokenText: clue.text);
              }
            },
            icon: Icon(playing ? Icons.replay_rounded : Icons.play_arrow_rounded),
            label: Text(playing ? 'PLAY AGAIN' : 'PLAY CLUE'),
          ),
        ),
        if ((clue.text ?? '').isNotEmpty) ...[
          const SizedBox(height: RD.md),
          Text('TRANSCRIPT', style: RD.sectionLabel.copyWith(color: Colors.white54)),
          const SizedBox(height: RD.xs),
          Text(clue.text!, style: RD.body.copyWith(color: Colors.white70, fontSize: 14, height: 1.5)),
        ],
      ],
    );
  }
}
