import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/gps/gps_connection.dart';
import 'package:explorer_os_mobile/features/gps/presentation/gps_status_card.dart';
import 'package:explorer_os_mobile/features/gps/providers/gps_status_provider.dart';
import 'package:explorer_os_mobile/features/location_intelligence/data/location_content_repository.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';
import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/discovery/nearby_narration_controller.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_state.dart';
import 'package:explorer_os_mobile/features/weather/weather_service.dart';

/// Explorer Mode — the full-screen driving companion. Big, glanceable, minimal:
/// current road/county, weather, the destination coming up (with distance),
/// what's playing + what's next, and large touch controls.
class ExplorerModeScreen extends ConsumerStatefulWidget {
  const ExplorerModeScreen({super.key});
  @override
  ConsumerState<ExplorerModeScreen> createState() => _ExplorerModeScreenState();
}

class _P {
  static const bg = Color(0xFF0A0F0C);
  static const card = Color(0xFF17211B);
  static const green = Color(0xFF33B074);
  static const gold = Color(0xFFF2B33D);
  static const text = Color(0xFFF3F6F2);
  static const dim = Color(0xFF9CA8A1);
}

class _ExplorerModeScreenState extends ConsumerState<ExplorerModeScreen> {
  WeatherData? _weather;
  bool _skipGpsGate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gpsStatusProvider.notifier).requestAndStart().catchError(
          (_) => ref.read(gpsStatusProvider));
      _loadWeather();
    });
  }

  Future<void> _loadWeather() async {
    final c = ref.read(mapCenterProvider);
    final g = ref.read(gpsStatusProvider);
    final lat = c?.latitude ?? g.latitude;
    final lng = c?.longitude ?? g.longitude;
    if (lat == null || lng == null) return;
    final w = await ref.read(weatherClientProvider).fetch(lat, lng);
    if (mounted && w != null) setState(() => _weather = w);
  }

  @override
  Widget build(BuildContext context) {
    final travel = ref.watch(gpsControllerProvider);
    final ctx = ref.watch(locationContextProvider);
    final gps = ref.watch(gpsStatusProvider);
    // Explorer Mode never begins until a reliable GPS location is established.
    final conn = deriveGpsConnection(gps, county: ctx.county);
    if (!conn.reliable && !_skipGpsGate) {
      return Scaffold(
        backgroundColor: _P.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Icon(Icons.explore_rounded, color: _P.green),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('EXPLORER MODE',
                        style: TextStyle(
                            color: _P.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: _P.dim),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ]),
                const Spacer(),
                GpsStatusCard(
                  onContinueWithout: () => setState(() => _skipGpsGate = true),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      );
    }
    final playback = ref.watch(radioEngineControllerProvider);
    final radio = ref.read(radioEngineControllerProvider.notifier);
    final nearby = ref.watch(nearbyLocationsProvider);
    final playing = playback.status == PlaybackStatus.playing;

    final road = (travel.currentRoad ?? '').trim();
    final county = (travel.currentCounty ?? ctx.county ?? '').trim();
    NearbyLocationLike? upcoming;
    if (nearby.isNotEmpty) {
      final n = nearby.first;
      final mi = n.distanceMeters / 1609.344;
      upcoming = NearbyLocationLike(
        n.location.name,
        n.location.type.label,
        '${mi < 10 ? mi.toStringAsFixed(1) : mi.round()} mi',
      );
    }
    final nowTitle = playback.current?.segment.title;
    final nextTitle = playback.queue
        .map((q) => q.segment.title)
        .firstWhere((t) => t.trim().isNotEmpty, orElse: () => '');

    return Scaffold(
      backgroundColor: _P.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header.
              Row(children: [
                const Icon(Icons.explore_rounded, color: _P.green),
                const SizedBox(width: 8),
                const Text('EXPLORER MODE',
                    style: TextStyle(
                        color: _P.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: _P.dim),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ]),
              const SizedBox(height: 8),
              // Where.
              Text(road.isNotEmpty ? road : 'On the road',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: _P.text, fontSize: 30, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Row(children: [
                if (county.isNotEmpty) ...[
                  const Icon(Icons.place_rounded, size: 16, color: _P.green),
                  const SizedBox(width: 6),
                  Text('$county County',
                      style: const TextStyle(color: _P.dim, fontSize: 15)),
                ],
                if (_weather?.temperatureF != null ||
                    _weather?.highF != null) ...[
                  const SizedBox(width: 16),
                  const Icon(Icons.wb_sunny_rounded, size: 16, color: _P.gold),
                  const SizedBox(width: 6),
                  Text(
                      '${(_weather!.temperatureF ?? _weather!.highF)!.round()}°'
                      ' · ${_weather!.condition}',
                      style: const TextStyle(color: _P.dim, fontSize: 15)),
                ],
              ]),
              const SizedBox(height: 20),
              // Up next destination.
              _upNext(upcoming),
              const SizedBox(height: 16),
              // Now playing + next story.
              _playingCard(nowTitle, nextTitle),
              const Spacer(),
              // Large controls.
              _controls(playing, radio),
            ],
          ),
        ),
      ),
    );
  }

  Widget _upNext(NearbyLocationLike? upcoming) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: _P.card, borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('COMING UP',
                  style: TextStyle(
                      color: _P.dim,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
              const SizedBox(height: 6),
              Text(upcoming?.name ?? 'Exploring the area',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: _P.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
              if (upcoming != null)
                Text(
                    '${upcoming.typeLabel} · ${upcoming.milesLabel} ahead',
                    style: const TextStyle(color: _P.green, fontSize: 14)),
            ],
          ),
        ),
        const Icon(Icons.navigation_rounded, color: _P.green, size: 40),
      ]),
    );
  }

  Widget _playingCard(String? nowTitle, String nextTitle) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: _P.card, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('NOW PLAYING',
              style: TextStyle(
                  color: _P.dim,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
          const SizedBox(height: 6),
          Text((nowTitle ?? '').trim().isNotEmpty ? nowTitle! : 'Sunshine Travel Radio',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: _P.text, fontSize: 20, fontWeight: FontWeight.w700)),
          if (nextTitle.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Next: $nextTitle',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _P.dim, fontSize: 14)),
          ],
        ],
      ),
    );
  }

  Widget _controls(bool playing, RadioEngineController radio) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _round(Icons.skip_previous_rounded, 64, radio.previous),
            _round(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                88,
                playing ? radio.pause : radio.play,
                filled: true),
            _round(Icons.skip_next_rounded, 64, radio.skip),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 62,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _P.card,
              foregroundColor: _P.text,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
            ),
            onPressed: () => ref
                .read(nearbyNarrationControllerProvider.notifier)
                .narrateNearest(),
            icon: const Icon(Icons.near_me_rounded, color: _P.green, size: 26),
            label: const Text("What's Near Me?",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _round(IconData icon, double size, VoidCallback onTap,
      {bool filled = false}) {
    return Material(
      color: filled ? _P.green : _P.card,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon,
              color: filled ? Colors.white : _P.text, size: size * 0.5),
        ),
      ),
    );
  }
}

/// Lightweight adapter so the "coming up" card doesn't depend on the engine type
/// directly (keeps the widget simple + testable).
class NearbyLocationLike {
  const NearbyLocationLike(this.name, this.typeLabel, this.milesLabel);
  final String name;
  final String typeLabel;
  final String milesLabel;
}
