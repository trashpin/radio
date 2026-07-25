import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/error/app_exception.dart';
import 'package:explorer_os_mobile/core/error/error_handler.dart';
import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/destinations/providers/destinations_provider.dart';
import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_queue_item.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_state.dart';
import 'package:explorer_os_mobile/features/radio/presentation/stations_screen.dart';
import 'package:explorer_os_mobile/features/radio/providers/radio_engine_providers.dart';
import 'package:explorer_os_mobile/features/radio/providers/radio_session_provider.dart';
import 'package:explorer_os_mobile/shared/models/destination.dart';
import 'package:explorer_os_mobile/shared/models/radio_station.dart';

/// Palette for the immersive (dark) Radio player — warm sunset orange accent.
class _RadioPalette {
  static const Color bg = Color(0xFF0C120F);
  static const Color panel = Color(0xFF171F1B);
  static const Color panelAlt = Color(0xFF212B26);
  static const Color accent = Color(0xFFEE7B2E); // sunset orange
  static const Color textPrimary = Color(0xFFF3F6F2);
  static const Color textSecondary = Color(0xFF9AA6A0);
  static const Color textFaint = Color(0xFF6E7A74);
}

/// Guide narration intensity (Light / Standard / Immersive).
enum GuideExperience { light, standard, immersive }

extension _GuideLabel on GuideExperience {
  String get label => switch (this) {
        GuideExperience.light => 'Light',
        GuideExperience.standard => 'Standard',
        GuideExperience.immersive => 'Immersive',
      };
}

/// The Explorer Radio player (automotive infotainment style).
class RadioScreen extends ConsumerWidget {
  const RadioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(radioSessionProvider);
    return Scaffold(
      backgroundColor: _RadioPalette.bg,
      body: session.when(
        loading: () =>
            const _RadioMessage(message: 'Tuning in…', spinner: true),
        error: (error, stack) {
          final exception =
              error is AppException ? error : ErrorHandler.from(error, stack);
          return _RadioMessage(
            message: exception.message,
            onRetry: () => ref.invalidate(radioSessionProvider),
          );
        },
        data: (station) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: _Player(station: station),
          ),
        ),
      ),
    );
  }
}

class _RadioMessage extends StatelessWidget {
  const _RadioMessage({required this.message, this.spinner = false, this.onRetry});

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
              const CircularProgressIndicator(color: _RadioPalette.accent),
              const Gap.v(AppSpacing.lg),
            ],
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _RadioPalette.textSecondary)),
            if (onRetry != null) ...[
              const Gap.v(AppSpacing.lg),
              TextButton(
                onPressed: onRetry,
                child: const Text('Try again',
                    style: TextStyle(color: _RadioPalette.accent)),
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
  GuideExperience _guide = GuideExperience.standard;
  double _volume = 0.7;

  Destination? _destination() {
    final all = ref.read(destinationsProvider).value ?? const [];
    for (final d in all) {
      if (d.id == widget.station.destinationId) return d;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final playback = ref.watch(radioEngineControllerProvider);
    final controller = ref.read(radioEngineControllerProvider.notifier);
    final nowPlaying = playback.current?.segment;
    final isPlaying = playback.status == PlaybackStatus.playing;
    final dest = _destination();

    final stationTitle = widget.station.name.toUpperCase();
    final tagline = (widget.station.description?.isNotEmpty ?? false)
        ? widget.station.description!
        : 'Where the Journey Meets the Music';
    final upNext =
        playback.queue.where((q) => q.segment.title.isNotEmpty).take(3).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 130),
      children: [
        _hero(),
        const Gap.v(AppSpacing.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            children: [
              Text(stationTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: _RadioPalette.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5)),
              const Gap.v(AppSpacing.xs),
              Text(tagline,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: _RadioPalette.accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
              const Gap.v(AppSpacing.lg),
              _InfoStrip(park: dest?.name, location: dest?.location),
              const Gap.v(AppSpacing.xl),
              _nowPlaying(nowPlaying?.title, nowPlaying?.artist, nowPlaying?.album),
              const Gap.v(AppSpacing.lg),
              _TrackProgress(
                trackKey: nowPlaying?.id ?? '',
                duration: (nowPlaying?.duration ?? Duration.zero) > Duration.zero
                    ? nowPlaying!.duration
                    : null,
                isPlaying: isPlaying,
              ),
              const Gap.v(AppSpacing.lg),
              _transport(isPlaying: isPlaying, controller: controller),
              const Gap.v(AppSpacing.xl),
              Row(
                children: [
                  Expanded(child: _guideCard()),
                  const Gap.h(AppSpacing.md),
                  Expanded(child: _aiRangerCard()),
                ],
              ),
              const Gap.v(AppSpacing.xl),
              _upNext(upNext),
              const Gap.v(AppSpacing.xl),
              _volumeRow(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _hero() {
    final url = widget.station.imageUrl;
    return SizedBox(
      height: 320,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url != null && url.isNotEmpty)
            Image.network(url, fit: BoxFit.cover)
          else
            const ColoredBox(color: _RadioPalette.panel),
          // Fade the bottom into the page background.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, _RadioPalette.bg],
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
              child: Row(
                children: [
                  _circleButton(
                    Icons.grid_view_rounded,
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const StationsScreen()),
                    ),
                  ),
                  const Spacer(),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.filter_hdr_rounded,
                          color: Colors.white, size: 20),
                      const SizedBox(height: 2),
                      RichText(
                        text: const TextSpan(
                          children: [
                            TextSpan(
                                text: 'EXPLORER',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1)),
                            TextSpan(
                                text: 'OS',
                                style: TextStyle(
                                    color: _RadioPalette.accent,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1)),
                          ],
                        ),
                      ),
                      const Text('— RADIO —',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 9,
                              letterSpacing: 3)),
                    ],
                  ),
                  const Spacer(),
                  _circleButton(
                    _favorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    () => setState(() => _favorite = !_favorite),
                    tint: _favorite ? _RadioPalette.accent : Colors.white,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap, {Color tint = Colors.white}) {
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Icon(icon, color: tint, size: 22),
        ),
      ),
    );
  }

  Widget _nowPlaying(String? title, String? artist, String? album) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title ?? 'Press play to start',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: _RadioPalette.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              if (artist != null && artist.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(artist,
                    style: const TextStyle(
                        color: _RadioPalette.textSecondary, fontSize: 14)),
              ],
              if (album != null && album.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(album,
                    style: const TextStyle(
                        color: _RadioPalette.textFaint,
                        fontSize: 13,
                        fontStyle: FontStyle.italic)),
              ],
            ],
          ),
        ),
        IconButton(
          onPressed: () => setState(() => _favorite = !_favorite),
          icon: Icon(
            _favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: _favorite ? _RadioPalette.accent : _RadioPalette.textSecondary,
          ),
        ),
        const Icon(Icons.more_vert_rounded, color: _RadioPalette.textSecondary),
      ],
    );
  }

  Widget _transport({required bool isPlaying, required RadioEngineController controller}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _transportBtn(Icons.shuffle_rounded, 'SHUFFLE', _shuffle,
            () => setState(() => _shuffle = !_shuffle)),
        _transportBtn(Icons.skip_previous_rounded, 'PREV', false,
            controller.previous),
        _playButton(isPlaying, controller),
        _transportBtn(Icons.skip_next_rounded, 'NEXT', false, controller.skip),
        _transportBtn(Icons.repeat_rounded, 'REPEAT', _repeat,
            () => setState(() => _repeat = !_repeat)),
      ],
    );
  }

  Widget _transportBtn(IconData icon, String label, bool active, VoidCallback onTap) {
    final color = active ? _RadioPalette.accent : _RadioPalette.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.pillAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1)),
          ],
        ),
      ),
    );
  }

  Widget _playButton(bool isPlaying, RadioEngineController controller) {
    return GestureDetector(
      onTap: isPlaying ? controller.pause : controller.play,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: _RadioPalette.accent,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: _RadioPalette.accent.withValues(alpha: 0.5),
                blurRadius: 26,
                spreadRadius: 2),
          ],
        ),
        child: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white, size: 40),
      ),
    );
  }

  Widget _guideCard() {
    return _panelCard(
      child: Row(
        children: [
          const Icon(Icons.equalizer_rounded, color: _RadioPalette.accent, size: 24),
          const Gap.h(AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('GUIDE EXPERIENCE',
                    style: TextStyle(
                        color: _RadioPalette.accent,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1)),
                const SizedBox(height: 2),
                Text(_guide.label,
                    style: const TextStyle(
                        color: _RadioPalette.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          PopupMenuButton<GuideExperience>(
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                color: _RadioPalette.textSecondary),
            onSelected: (g) => setState(() => _guide = g),
            itemBuilder: (context) => [
              for (final g in GuideExperience.values)
                PopupMenuItem(value: g, child: Text(g.label)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _aiRangerCard() {
    return _panelCard(
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI Ranger — ask about the park (coming soon)')),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('AI RANGER',
                    style: TextStyle(
                        color: _RadioPalette.accent,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1)),
                SizedBox(height: 2),
                Text('Ask me anything\nabout the park!',
                    style: TextStyle(
                        color: _RadioPalette.textPrimary,
                        fontSize: 13,
                        height: 1.2)),
              ],
            ),
          ),
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: Color(0xFF2E9E6B),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.smart_toy_rounded,
                color: Colors.white, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _panelCard({required Widget child, VoidCallback? onTap}) {
    return Material(
      color: _RadioPalette.panel,
      borderRadius: AppRadius.lgAll,
      child: InkWell(
        borderRadius: AppRadius.lgAll,
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(AppSpacing.md), child: child),
      ),
    );
  }

  Widget _upNext(List<PlaybackQueueItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('UP NEXT',
                style: TextStyle(
                    color: _RadioPalette.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            Row(
              children: const [
                Text('View Queue',
                    style: TextStyle(
                        color: _RadioPalette.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                Icon(Icons.chevron_right_rounded, color: _RadioPalette.accent, size: 18),
              ],
            ),
          ],
        ),
        const Gap.v(AppSpacing.sm),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text('Nothing queued',
                style: TextStyle(color: _RadioPalette.textSecondary)),
          )
        else
          for (final q in items) _upNextTile(q),
      ],
    );
  }

  Widget _upNextTile(PlaybackQueueItem q) {
    final seg = q.segment;
    final dur = seg.duration > Duration.zero
        ? '${seg.duration.inMinutes}:${(seg.duration.inSeconds % 60).toString().padLeft(2, '0')}'
        : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: AppRadius.smAll,
              gradient: const LinearGradient(
                colors: [Color(0xFF3A2A1A), Color(0xFF6B4A2B)],
              ),
            ),
            child: const Icon(Icons.music_note_rounded,
                color: Colors.white70, size: 20),
          ),
          const Gap.h(AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(seg.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: _RadioPalette.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                if (seg.artist != null)
                  Text(seg.artist!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _RadioPalette.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          if (dur.isNotEmpty)
            Text(dur,
                style: const TextStyle(
                    color: _RadioPalette.textSecondary, fontSize: 12)),
          const Gap.h(AppSpacing.sm),
          const Icon(Icons.drag_handle_rounded,
              color: _RadioPalette.textFaint, size: 20),
        ],
      ),
    );
  }

  Widget _volumeRow() {
    return Row(
      children: [
        const Icon(Icons.volume_down_rounded,
            color: _RadioPalette.textSecondary, size: 22),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _RadioPalette.accent,
              inactiveTrackColor: _RadioPalette.panelAlt,
              thumbColor: Colors.white,
              trackHeight: 4,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: _volume,
              onChanged: (v) {
                setState(() => _volume = v);
                ref.read(radioEngineServiceProvider).setVolume(v);
              },
            ),
          ),
        ),
        const Icon(Icons.volume_up_rounded,
            color: _RadioPalette.textSecondary, size: 22),
      ],
    );
  }
}

/// ON AIR pill + Current Park / Location / Elevation info strip.
class _InfoStrip extends StatelessWidget {
  const _InfoStrip({this.park, this.location});
  final String? park;
  final String? location;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: _RadioPalette.panel,
        borderRadius: AppRadius.lgAll,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: AppRadius.pillAll,
              border: Border.all(color: _RadioPalette.accent),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.podcasts_rounded, color: _RadioPalette.accent, size: 14),
                SizedBox(width: 4),
                Text('ON AIR',
                    style: TextStyle(
                        color: _RadioPalette.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          _divider(),
          _col(Icons.forest_rounded, 'CURRENT PARK', park ?? '—'),
          _divider(),
          _col(Icons.place_rounded, 'LOCATION', location ?? 'On the road'),
          _divider(),
          _col(Icons.terrain_rounded, 'ELEVATION', '—'),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 34,
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        color: _RadioPalette.panelAlt,
      );

  Widget _col(IconData icon, String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, color: _RadioPalette.accent, size: 12),
              const SizedBox(width: 3),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: _RadioPalette.accent,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: _RadioPalette.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.15)),
        ],
      ),
    );
  }
}

/// Playback progress bar. The engine carries no live audio position, so this
/// advances a local elapsed timer while playing (reset on track change).
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
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.duration?.inSeconds.toDouble();
    final fraction =
        (total != null && total > 0) ? (_elapsed / total).clamp(0.0, 1.0) : 0.0;
    return Row(
      children: [
        Text(_fmt(_elapsed),
            style: const TextStyle(color: _RadioPalette.textSecondary, fontSize: 12)),
        const Gap.h(AppSpacing.md),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _RadioPalette.accent,
              inactiveTrackColor: _RadioPalette.panelAlt,
              thumbColor: _RadioPalette.accent,
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: total != null ? fraction : 0,
              onChanged: (_) {},
            ),
          ),
        ),
        const Gap.h(AppSpacing.md),
        Text(total != null ? _fmt(total) : '--:--',
            style: const TextStyle(color: _RadioPalette.textSecondary, fontSize: 12)),
      ],
    );
  }
}
