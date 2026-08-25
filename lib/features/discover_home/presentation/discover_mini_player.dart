import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_state.dart';

/// "▶ Sunshine Travel Radio" — a glanceable now-playing bar so Radio stays
/// reachable/controllable from every primary tab without a tab of its own
/// (see `AppShell`'s doc comment). Reads the SAME
/// `radioEngineControllerProvider` the full Radio screen already uses — no
/// second playback engine, no rebuilt music system. Tapping it opens the
/// full Radio screen ([AppRoute.radio], a pushed route reached from every
/// primary tab and from the More menu); nothing here controls playback
/// directly beyond the one play/pause button, which calls the same engine
/// every other play/pause button in the app calls.
class DiscoverMiniPlayer extends ConsumerWidget {
  const DiscoverMiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(radioEngineControllerProvider);
    final controller = ref.read(radioEngineControllerProvider.notifier);
    final isPlaying = playback.status == PlaybackStatus.playing;
    final title = (playback.current?.segment.title.trim().isNotEmpty ?? false)
        ? playback.current!.segment.title
        : 'Sunshine Travel Radio';

    return Material(
      color: RD.panel,
      borderRadius: BorderRadius.circular(RD.rPill),
      child: InkWell(
        borderRadius: BorderRadius.circular(RD.rPill),
        onTap: () => context.push(AppRoute.radio.path),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: RD.md, vertical: RD.sm),
          child: Row(children: [
            Icon(isPlaying ? Icons.graphic_eq_rounded : Icons.podcasts_rounded,
                color: RD.green, size: 20),
            const SizedBox(width: RD.sm),
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RD.caption.copyWith(color: RD.textPrimary, fontWeight: FontWeight.w600)),
            ),
            IconButton(
              iconSize: 28,
              color: RD.green,
              onPressed: isPlaying ? controller.pause : controller.play,
              icon: Icon(isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
            ),
          ]),
        ),
      ),
    );
  }
}
