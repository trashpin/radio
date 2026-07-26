import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_state.dart';
import 'package:explorer_os_mobile/features/radio/providers/radio_session_provider.dart';
import 'package:explorer_os_mobile/features/radio/providers/stations_provider.dart';
import 'package:explorer_os_mobile/shared/models/radio_station.dart';

/// The Home screen — a forest radio station selector.
///
/// Pick a music station (Country / Rock / Top Hits / Kids) to start exploring.
/// Every station shares the exact same educational content (GPS stories,
/// wildlife, "I See Something", etc.) — only the music differs. The Guide button
/// opens the guided exploration features (map, GPS tour, POIs).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const _bg = Color(0xFF0A0F0C);
  static const _green = Color(0xFF8FC46B);

  static const _hero =
      'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=1200';

  static const _descriptions = <String, String>{
    'country':
        'Country music inspired by forests, camping, rivers, wildlife, and small-town Florida.',
    'rock': 'Classic rock and modern rock with an adventurous outdoor feel.',
    'hits': 'Current hit music mixed with immersive park exploration.',
    'kids':
        'Family-friendly music with fun, engaging narration for younger visitors.',
  };

  void _tune(BuildContext context, WidgetRef ref, RadioStation station) {
    ref.read(selectedStationProvider.notifier).select(station);
    ref.invalidate(radioSessionProvider);
    context.go(AppRoute.radio.path);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(radioStationCatalogProvider);
    final selected = ref.watch(selectedStationProvider);
    final playing = ref.watch(radioEngineControllerProvider).status ==
        PlaybackStatus.playing;
    final stations = async.value ?? stationCatalog;

    return Scaffold(
      backgroundColor: _bg,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          _header(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
            child: Column(
              children: [
                for (final s in stations) ...[
                  _StationCard(
                    station: s,
                    description: _descriptions[s.id] ?? s.description ?? '',
                    active: selected?.id == s.id,
                    playing: selected?.id == s.id && playing,
                    onTap: () => _tune(context, ref, s),
                  ),
                  const Gap.v(AppSpacing.md),
                ],
                const Gap.v(AppSpacing.sm),
                _guideButton(context),
                const Gap.v(AppSpacing.lg),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return SizedBox(
      height: 240,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(_hero, fit: BoxFit.cover,
              errorBuilder: (c, e, s) => const ColoredBox(color: _bg)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black26, _bg],
                stops: [0.3, 1.0],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: const [
                    Icon(Icons.forest_rounded, color: _green, size: 22),
                    SizedBox(width: 8),
                    Icon(Icons.podcasts_rounded, color: _green, size: 20),
                  ]),
                  const SizedBox(height: 8),
                  const Text('OCALA NATIONAL FOREST RADIO',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5)),
                  const SizedBox(height: 4),
                  const Text('Choose Your Station',
                      style: TextStyle(
                          color: _green,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _guideButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => context.go(AppRoute.map.path),
        style: OutlinedButton.styleFrom(
          foregroundColor: _green,
          side: const BorderSide(color: _green),
          minimumSize: const Size(0, 60),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        icon: const Icon(Icons.explore_rounded),
        label: const Text('Guide  ·  Map, GPS Tour & Ranger Tips',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _StationCard extends StatelessWidget {
  const _StationCard({
    required this.station,
    required this.description,
    required this.active,
    required this.playing,
    required this.onTap,
  });
  final RadioStation station;
  final String description;
  final bool active;
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = styleFor(station);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        height: 132,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: const Color(0xFF141C16),
          border: Border.all(
              color: active
                  ? style.accent
                  : Colors.white.withValues(alpha: 0.06),
              width: active ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            SizedBox(
              width: 128,
              height: double.infinity,
              child: Stack(fit: StackFit.expand, children: [
                if (station.imageUrl != null)
                  Image.network(station.imageUrl!, fit: BoxFit.cover,
                      errorBuilder: (c, e, s) =>
                          ColoredBox(color: style.accent.withValues(alpha: 0.4)))
                else
                  ColoredBox(color: style.accent.withValues(alpha: 0.4)),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, const Color(0xFF141C16)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(children: [
                      Icon(style.icon, color: style.accent, size: 16),
                      const SizedBox(width: 6),
                      Text(style.genre.toUpperCase(),
                          style: TextStyle(
                              color: style.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1)),
                    ]),
                    const SizedBox(height: 2),
                    Text(station.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 11,
                            height: 1.25)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: playing
                  ? _MiniEqualizer(color: style.accent)
                  : Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: style.accent, width: 2),
                      ),
                      child: Icon(Icons.play_arrow_rounded,
                          color: style.accent, size: 26),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniEqualizer extends StatefulWidget {
  const _MiniEqualizer({required this.color});
  final Color color;
  @override
  State<_MiniEqualizer> createState() => _MiniEqualizerState();
}

class _MiniEqualizerState extends State<_MiniEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 650))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 46,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          double h(int i) {
            final p = (_c.value + i * 0.3) % 1.0;
            return 8 + (p < 0.5 ? p : 1 - p) * 26;
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 4; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Container(
                    width: 4,
                    height: h(i),
                    decoration: BoxDecoration(
                        color: widget.color,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
