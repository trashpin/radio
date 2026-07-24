import 'dart:async';

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

/// Palette for the immersive (dark) Radio player. Media/"now playing" screens
/// read best on a dark canvas, so this screen styles itself explicitly rather
/// than depending on the app's light/dark mode.
class _RadioPalette {
  static const Color bg = Color(0xFF0E1512);
  static const Color panel = Color(0xFF1B2420);
  static const Color panelAlt = Color(0xFF232E29);
  static const Color gold = Color(0xFFF2B33D);
  static const Color textPrimary = Color(0xFFF3F6F2);
  static const Color textSecondary = Color(0xFF9CA8A1);
  static const Color live = Color(0xFF43C97C);
}

/// The Explorer Radio player.
///
/// Watches [radioSessionProvider] (loads the station + playlist and attaches
/// audio output) and [radioEngineControllerProvider] (live playback state).
/// Transport controls drive the engine, which drives the audio adapter.
class RadioScreen extends ConsumerWidget {
  const RadioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(radioSessionProvider);

    return Scaffold(
      backgroundColor: _RadioPalette.bg,
      body: session.when(
        loading: () => const _RadioMessage(message: 'Tuning in…', spinner: true),
        error: (error, stack) {
          final exception =
              error is AppException ? error : ErrorHandler.from(error, stack);
          return _RadioMessage(
            message: exception.message,
            onRetry: () => ref.invalidate(radioSessionProvider),
          );
        },
        data: (station) => _Player(station: station),
      ),
    );
  }
}

/// Simple dark loading/error state matching the player's canvas.
class _RadioMessage extends StatelessWidget {
  const _RadioMessage({
    required this.message,
    this.spinner = false,
    this.onRetry,
  });

  final String message;
  final bool spinner;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spinner) ...[
              const CircularProgressIndicator(color: _RadioPalette.gold),
              const Gap.v(AppSpacing.lg),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _RadioPalette.textSecondary),
            ),
            if (onRetry != null) ...[
              const Gap.v(AppSpacing.lg),
              TextButton(
                onPressed: onRetry,
                child: const Text('Try again',
                    style: TextStyle(color: _RadioPalette.gold)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Player extends ConsumerStatefulWidget {
  const _Player({required this.station});

  final RadioStation station;

  @override
  ConsumerState<_Player> createState() => _PlayerState();
}

class _PlayerState extends ConsumerState<_Player> {
  bool _favorite = false;
  bool _shuffle = false;
  bool _repeat = false;

  @override
  Widget build(BuildContext context) {
    final playback = ref.watch(radioEngineControllerProvider);
    final controller = ref.read(radioEngineControllerProvider.notifier);
    final nowPlaying = playback.current?.segment;
    final isPlaying = playback.status == PlaybackStatus.playing;

    // Big title = the destination name (station name minus a trailing "Radio").
    final title = widget.station.name.replaceAll(
      RegExp(r'\s*Radio$', caseSensitive: false),
      '',
    );
    final trackTitle = nowPlaying?.title ?? 'Press play to start';
    final upNext = playback.queue.isNotEmpty ? playback.queue.first : null;
    final duration = (nowPlaying?.duration ?? Duration.zero) > Duration.zero
        ? nowPlaying!.duration
        : null;

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.xl,
          130,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            const Gap.v(AppSpacing.xl),
            Text(
              'FLORIDA EXPLORER',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _RadioPalette.gold,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
            const Gap.v(AppSpacing.sm),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _RadioPalette.textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const Gap.v(AppSpacing.md),
            const Center(child: _LiveBadge()),
            const Gap.v(AppSpacing.xl),
            _artwork(isPlaying: isPlaying, controller: controller),
            const Gap.v(AppSpacing.xl),
            _trackRow(trackTitle),
            const Gap.v(AppSpacing.lg),
            const _ReportButton(),
            const Gap.v(AppSpacing.lg),
            _TrackProgress(
              trackKey: nowPlaying?.id ?? '',
              duration: duration,
              isPlaying: isPlaying,
            ),
            const Gap.v(AppSpacing.md),
            _transport(isPlaying: isPlaying, controller: controller),
            const Gap.v(AppSpacing.xl),
            _UpNextCard(title: upNext?.segment.title),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        _circleIcon(Icons.menu_rounded, onTap: () {}),
        Expanded(
          child: Column(
            children: const [
              Icon(Icons.filter_hdr_rounded,
                  color: _RadioPalette.textPrimary, size: 18),
              SizedBox(height: 2),
              Text(
                'EXPLOREROS',
                style: TextStyle(
                  color: _RadioPalette.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                ),
              ),
              Text(
                'EXPLORER RADIO',
                style: TextStyle(
                  color: _RadioPalette.textSecondary,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2.5,
                ),
              ),
            ],
          ),
        ),
        _circleIcon(Icons.cast_rounded, onTap: () {}),
      ],
    );
  }

  Widget _artwork({required bool isPlaying, required RadioEngineController controller}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _SkipButton(
          icon: Icons.replay_rounded,
          label: '15',
          onTap: controller.previous,
        ),
        Flexible(
          child: _VinylArtwork(
            imageUrl: widget.station.imageUrl,
            isPlaying: isPlaying,
          ),
        ),
        _SkipButton(
          icon: Icons.forward_rounded,
          label: '15',
          onTap: controller.skip,
        ),
      ],
    );
  }

  Widget _trackRow(String trackTitle) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                trackTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _RadioPalette.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'ExplorerOS Original',
                style: TextStyle(
                    color: _RadioPalette.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => setState(() => _favorite = !_favorite),
          icon: Icon(
            _favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: _favorite ? _RadioPalette.gold : _RadioPalette.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _transport({required bool isPlaying, required RadioEngineController controller}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _toggleIcon(Icons.shuffle_rounded, _shuffle,
            () => setState(() => _shuffle = !_shuffle)),
        _circleIcon(Icons.skip_previous_rounded,
            onTap: controller.previous, size: 30),
        // Prominent gold play/pause.
        GestureDetector(
          onTap: isPlaying ? controller.pause : controller.play,
          child: Container(
            width: 68,
            height: 68,
            decoration: const BoxDecoration(
              color: _RadioPalette.gold,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x66F2B33D),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: const Color(0xFF1A1200),
              size: 38,
            ),
          ),
        ),
        _circleIcon(Icons.skip_next_rounded, onTap: controller.skip, size: 30),
        _toggleIcon(Icons.repeat_rounded, _repeat,
            () => setState(() => _repeat = !_repeat)),
      ],
    );
  }

  Widget _toggleIcon(IconData icon, bool active, VoidCallback onTap) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon,
          color: active ? _RadioPalette.gold : _RadioPalette.textSecondary),
    );
  }

  Widget _circleIcon(IconData icon,
      {required VoidCallback onTap, double size = 22}) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Icon(icon, color: _RadioPalette.textPrimary, size: size),
      ),
    );
  }
}

/// Green "● LIVE" pill.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _RadioPalette.live.withValues(alpha: 0.16),
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.circle, color: _RadioPalette.live, size: 8),
          SizedBox(width: 6),
          Text(
            'LIVE',
            style: TextStyle(
              color: _RadioPalette.live,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small skip control with an icon over a "15 SEC" label.
class _SkipButton extends StatelessWidget {
  const _SkipButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.pillAll,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _RadioPalette.textPrimary, size: 28),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    color: _RadioPalette.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
            const Text('SEC',
                style: TextStyle(
                    color: _RadioPalette.textSecondary,
                    fontSize: 8,
                    letterSpacing: 1)),
          ],
        ),
      ),
    );
  }
}

/// Square cover art with a vinyl record peeking out to the right; the disc
/// rotates while playing.
class _VinylArtwork extends StatefulWidget {
  const _VinylArtwork({required this.imageUrl, required this.isPlaying});

  final String? imageUrl;
  final bool isPlaying;

  @override
  State<_VinylArtwork> createState() => _VinylArtworkState();
}

class _VinylArtworkState extends State<_VinylArtwork>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isPlaying) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant _VinylArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.isPlaying && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = widget.imageUrl != null && widget.imageUrl!.isNotEmpty;
    return AspectRatio(
      aspectRatio: 1.35,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxHeight;
          final disc = size * 0.94;
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Vinyl disc, offset to the right and partly behind the cover.
              Positioned(
                right: 0,
                top: (size - disc) / 2,
                child: RotationTransition(
                  turns: _spin,
                  child: _VinylDisc(size: disc),
                ),
              ),
              // Square cover art.
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  borderRadius: AppRadius.lgAll,
                  gradient: AppColors.heroGradient,
                  image: hasImage
                      ? DecorationImage(
                          image: NetworkImage(widget.imageUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x99000000),
                        blurRadius: 28,
                        offset: Offset(0, 14)),
                  ],
                ),
                child: hasImage
                    ? null
                    : const Center(
                        child: Icon(Icons.radio_rounded,
                            size: 64, color: Colors.white70),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A stylized vinyl record (concentric grooves + center label).
class _VinylDisc extends StatelessWidget {
  const _VinylDisc({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFF2A2A2A), Color(0xFF0A0A0A)],
          stops: [0.4, 1],
        ),
        border: Border.all(color: const Color(0xFF3A3A3A), width: 2),
      ),
      child: Center(
        child: Container(
          width: size * 0.34,
          height: size * 0.34,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: _RadioPalette.gold,
          ),
          child: Center(
            child: Container(
              width: size * 0.06,
              height: size * 0.06,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF0A0A0A),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "I SEE SOMETHING" reporting call-to-action.
class _ReportButton extends StatelessWidget {
  const _ReportButton();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _RadioPalette.panel,
      borderRadius: AppRadius.lgAll,
      child: InkWell(
        borderRadius: AppRadius.lgAll,
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Report a sighting — coming soon')),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: _RadioPalette.panelAlt,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.travel_explore_rounded,
                    color: _RadioPalette.gold, size: 22),
              ),
              const Gap.h(AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('I SEE SOMETHING',
                        style: TextStyle(
                            color: _RadioPalette.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5)),
                    SizedBox(height: 2),
                    Text('Report wildlife, places, and more',
                        style: TextStyle(
                            color: _RadioPalette.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: _RadioPalette.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Playback progress bar. The engine's [PlaybackState] carries no live audio
/// position, so this advances a local elapsed timer while playing (reset on
/// track change) to give an accurate elapsed-since-play readout against the
/// segment's known [duration].
class _TrackProgress extends StatefulWidget {
  const _TrackProgress({
    required this.trackKey,
    required this.duration,
    required this.isPlaying,
  });

  final String trackKey;
  final Duration? duration;
  final bool isPlaying;

  @override
  State<_TrackProgress> createState() => _TrackProgressState();
}

class _TrackProgressState extends State<_TrackProgress> {
  Timer? _timer;
  double _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _TrackProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trackKey != widget.trackKey) _elapsed = 0;
    if (oldWidget.isPlaying != widget.isPlaying ||
        oldWidget.trackKey != widget.trackKey) {
      _syncTimer();
    }
  }

  void _syncTimer() {
    _timer?.cancel();
    if (widget.isPlaying) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        final total = widget.duration?.inSeconds.toDouble();
        setState(() {
          _elapsed += 1;
          if (total != null && _elapsed > total) _elapsed = total;
        });
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmt(double seconds) {
    final s = seconds.round();
    final m = s ~/ 60;
    final r = s % 60;
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.duration?.inSeconds.toDouble();
    final fraction =
        (total != null && total > 0) ? (_elapsed / total).clamp(0.0, 1.0) : 0.0;
    return Row(
      children: [
        Text(_fmt(_elapsed),
            style: const TextStyle(
                color: _RadioPalette.textSecondary, fontSize: 12)),
        const Gap.h(AppSpacing.md),
        Expanded(
          child: ClipRRect(
            borderRadius: AppRadius.pillAll,
            child: LinearProgressIndicator(
              value: total != null ? fraction : null,
              minHeight: 4,
              backgroundColor: _RadioPalette.panelAlt,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(_RadioPalette.gold),
            ),
          ),
        ),
        const Gap.h(AppSpacing.md),
        Text(total != null ? _fmt(total) : '--:--',
            style: const TextStyle(
                color: _RadioPalette.textSecondary, fontSize: 12)),
      ],
    );
  }
}

/// "UP NEXT" card with a thumbnail, next-track title, and a queue icon.
class _UpNextCard extends StatelessWidget {
  const _UpNextCard({required this.title});
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _RadioPalette.panel,
        borderRadius: AppRadius.lgAll,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: AppRadius.mdAll,
              gradient: AppColors.sunsetGradient,
            ),
            child: const Icon(Icons.music_note_rounded,
                color: Colors.white, size: 22),
          ),
          const Gap.h(AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('UP NEXT',
                    style: TextStyle(
                        color: _RadioPalette.gold,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5)),
                const SizedBox(height: 2),
                Text(
                  title ?? 'Nothing queued',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: _RadioPalette.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
                const Text('ExplorerOS Original',
                    style: TextStyle(
                        color: _RadioPalette.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.queue_music_rounded,
              color: _RadioPalette.textSecondary),
        ],
      ),
    );
  }
}
