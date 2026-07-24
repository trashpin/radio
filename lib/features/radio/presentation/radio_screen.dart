import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/error/app_exception.dart';
import 'package:explorer_os_mobile/core/error/error_handler.dart';
import 'package:explorer_os_mobile/core/theme/app_colors.dart';
import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_state.dart';
import 'package:explorer_os_mobile/features/radio/providers/radio_session_provider.dart';
import 'package:explorer_os_mobile/shared/models/radio_station.dart';
import 'package:explorer_os_mobile/shared/widgets/error_view.dart';
import 'package:explorer_os_mobile/shared/widgets/loading_widget.dart';

/// The Explorer Radio player.
///
/// Watches [radioSessionProvider] (loads the station + playlist from the backend
/// and attaches audio output) and [radioEngineControllerProvider] (live
/// playback state). Transport controls drive the engine, which drives the audio
/// adapter — so pressing Play produces real sound once content is available.
class RadioScreen extends ConsumerWidget {
  const RadioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(radioSessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Radio')),
      body: session.when(
        loading: () => const LoadingWidget(message: 'Tuning in…'),
        error: (error, stack) => ErrorView(
          exception: error is AppException
              ? error
              : ErrorHandler.from(error, stack),
          onRetry: () => ref.invalidate(radioSessionProvider),
        ),
        data: (station) => _Player(station: station),
      ),
    );
  }
}

class _Player extends ConsumerWidget {
  const _Player({required this.station});

  final RadioStation station;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final playback = ref.watch(radioEngineControllerProvider);
    final controller = ref.read(radioEngineControllerProvider.notifier);
    final nowPlaying = playback.current?.segment;
    final isPlaying = playback.status == PlaybackStatus.playing;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        120,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Station "cover".
          AspectRatio(
            aspectRatio: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppColors.heroGradient,
                borderRadius: AppRadius.xlAll,
                image: (station.imageUrl != null && station.imageUrl!.isNotEmpty)
                    ? DecorationImage(
                        image: NetworkImage(station.imageUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: station.imageUrl == null
                  ? const Center(
                      child: Icon(Icons.radio_rounded,
                          size: 96, color: AppColors.textOnPrimary),
                    )
                  : null,
            ),
          ),
          const Gap.v(AppSpacing.xl),
          Text(station.name, style: theme.textTheme.headlineMedium),
          const Gap.v(AppSpacing.xs),
          Text(
            nowPlaying?.title ?? 'Press play to start',
            style: theme.textTheme.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const Gap.v(AppSpacing.xxl),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                iconSize: 40,
                onPressed: controller.previous,
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              FilledButton(
                onPressed: isPlaying ? controller.pause : controller.play,
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(AppSpacing.xl),
                ),
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 40,
                ),
              ),
              IconButton(
                iconSize: 40,
                onPressed: controller.skip,
                icon: const Icon(Icons.skip_next_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
