import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/error/app_exception.dart';
import 'package:explorer_os_mobile/core/error/error_handler.dart';
import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/features/destinations/providers/destinations_provider.dart';
import 'package:explorer_os_mobile/features/gps/providers/gps_status_provider.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/discovery/i_see_something_modal.dart';
import 'package:explorer_os_mobile/features/radio/discovery/nearby_narration_controller.dart';
import 'package:explorer_os_mobile/features/radio/discovery/observation_controller.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_queue_item.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_state.dart';
import 'package:explorer_os_mobile/features/radio/presentation/stations_screen.dart';
import 'package:explorer_os_mobile/features/radio/providers/radio_session_provider.dart';
import 'package:explorer_os_mobile/shared/models/destination.dart';
import 'package:explorer_os_mobile/shared/models/radio_station.dart';

/// Premium automotive-infotainment palette: black canvas, Explorer Green accent,
/// white type, soft panels with large radii.
class _RadioPalette {
  static const Color bg = Color(0xFF000000);
  static const Color panel = Color(0xFF121815);
  static const Color panelAlt = Color(0xFF1B231F);
  static const Color green = Color(0xFF35C56A); // Explorer Green
  static const Color greenSoft = Color(0xFF2A7D48);
  static const Color textPrimary = Color(0xFFF3F6F2);
  static const Color textSecondary = Color(0xFF9AA6A0);
  static const Color textFaint = Color(0xFF6E7A74);
  static const double radius = 22;
}

/// The broadcast host shown throughout the station (a UI label — the interface
/// never exposes the underlying content type, only what's on air and its host).
const String _stationHost = 'Ranger Jake';

/// The Explorer Radio player — a luxury-vehicle infotainment layout.
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
  const _RadioMessage(
      {required this.message, this.spinner = false, this.onRetry});

  final String message;
  final bool spinner;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spinner) ...[
              const CircularProgressIndicator(color: _RadioPalette.green),
              const SizedBox(height: 20),
            ],
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _RadioPalette.textSecondary)),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              TextButton(
                onPressed: onRetry,
                child: const Text('Try again',
                    style: TextStyle(color: _RadioPalette.green)),
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

/// Which temporary live "report" (if any) is currently interrupting the radio.
enum _Interruption {
  none('🎵', 'ExplorerOS Radio', _RadioPalette.green),
  iSeeSomething('👁', 'I See Something', Color(0xFF2C6E8F)),
  whatsNearMe('📍', "What's Near Me", Color(0xFFC58A2E));

  const _Interruption(this.emoji, this.label, this.color);
  final String emoji;
  final String label;
  final Color color;
}

class _PlayerState extends ConsumerState<_Player> {
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
    final obs = ref.watch(observationControllerProvider);
    final nearby = ref.watch(nearbyNarrationControllerProvider);
    final nowPlaying = playback.current?.segment;
    final isPlaying = playback.status == PlaybackStatus.playing;
    final dest = _destination();

    // A temporary live "report" (I See Something / What's Near Me) is on air —
    // it interrupts the station, then the radio resumes where it paused. The
    // indicator tracks the *narrating* state so it flips back to the station
    // automatically the moment the report ends.
    final interruption = (obs.active && obs.narrating)
        ? _Interruption.iSeeSomething
        : (nearby.active && nearby.narrating
            ? _Interruption.whatsNearMe
            : _Interruption.none);

    // Dynamic "now playing" title — whatever is on air right now, never its
    // internal category. During a report it's the report's subject.
    final title = switch (interruption) {
      _Interruption.iSeeSomething => obs.species!.commonName,
      _Interruption.whatsNearMe => nearby.location?.name ?? 'Nearby',
      _Interruption.none => nowPlaying?.title.isNotEmpty ?? false
          ? nowPlaying!.title
          : 'ExplorerOS Radio',
    };
    final playing = isPlaying ||
        (obs.active && obs.narrating) ||
        (nearby.active && nearby.narrating);

    void backToRadio() {
      if (obs.active) ref.read(observationControllerProvider.notifier).clear();
      if (nearby.active) {
        ref.read(nearbyNarrationControllerProvider.notifier).clear();
      }
    }

    final heroImage = obs.species?.heroImageUrl ?? widget.station.imageUrl;

    final upNext = playback.queue
        .where((q) => q.segment.title.trim().isNotEmpty)
        .take(3)
        .toList();

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              park: dest?.name ?? 'ExplorerOS',
              location: dest?.location ?? 'Florida, USA',
              onSettings: _openSettings,
            ),
            const SizedBox(height: 16),
            _ScenicCard(
              imageUrl: heroImage,
              location: dest?.name ?? 'ExplorerOS',
              landmark: _landmark(playback),
              glowing: obs.active && obs.narrating,
            ),
            const SizedBox(height: 16),
            _LiveIndicator(interruption: interruption),
            const SizedBox(height: 10),
            _NowPlayingCard(
              title: title,
              host: _stationHost,
              playing: playing,
              subtitle: interruption == _Interruption.iSeeSomething
                  ? obs.species!.scientificName
                  : null,
              onBackToRadio:
                  interruption != _Interruption.none ? backToRadio : null,
            ),
            const SizedBox(height: 18),
            _Controls(
              isPlaying: isPlaying,
              // During a report, Back restarts it; otherwise replays the
              // previous radio item.
              onPrevious: switch (interruption) {
                _Interruption.iSeeSomething => () => ref
                    .read(observationControllerProvider.notifier)
                    .observe(obs.species!),
                _Interruption.whatsNearMe => () => ref
                    .read(nearbyNarrationControllerProvider.notifier)
                    .narrateNearest(),
                _Interruption.none => controller.previous,
              },
              onPlayPause: isPlaying ? controller.pause : controller.play,
              // Next/Skip cancels an active report and resumes the song at the
              // exact spot; otherwise skips to the next radio item.
              onNext: controller.skip,
            ),
            const SizedBox(height: 20),
            _PrimaryAction(
              icon: Icons.near_me_rounded,
              title: "What's Near Me?",
              description:
                  'A quick live report on the closest place around you.',
              onTap: _whatsNearMe,
            ),
            const SizedBox(height: 12),
            _PrimaryAction(
              icon: Icons.visibility_rounded,
              title: 'I See Something',
              description:
                  'Take a photo or describe what you see and ExplorerOS will '
                  'identify and explain it.',
              tint: const Color(0xFF2C6E8F),
              onTap: () => showISeeSomething(context, ref),
            ),
            const SizedBox(height: 22),
            _ComingUpNext(items: upNext),
          ],
        ),
      ),
    );
  }

  /// "What's Near Me?" opens a list of nearby places (within ~20 miles). Picking
  /// one plays it as a temporary live report — the radio interrupts, narrates
  /// the chosen place, then resumes exactly where it paused.
  void _whatsNearMe() {
    // Make sure GPS is acquiring so the list can populate.
    ref.read(gpsStatusProvider.notifier).requestAndStart();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _RadioPalette.panel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _NearbyListSheet(
        onPick: (loc) {
          Navigator.of(context).pop();
          ref
              .read(nearbyNarrationControllerProvider.notifier)
              .narrateLocation(loc);
        },
      ),
    );
  }

  String? _landmark(PlaybackState playback) {
    final seg = playback.current?.segment;
    // Only spoken/location content is a "landmark"; a song title is not.
    if (seg == null || seg.type == AudioSegmentType.music) return null;
    final t = seg.title.trim();
    return t.isEmpty ? null : t;
  }

  // ── Advanced settings, moved off the main screen ─────────────────────────
  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _RadioPalette.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: _RadioPalette.panelAlt,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.grid_view_rounded,
                    color: _RadioPalette.green),
                title: const Text('Browse stations',
                    style: TextStyle(color: _RadioPalette.textPrimary)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const StationsScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_rounded,
                    color: _RadioPalette.green),
                title: const Text('App settings',
                    style: TextStyle(color: _RadioPalette.textPrimary)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.push(AppRoute.settings.path);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.park,
    required this.location,
    required this.onSettings,
  });

  final String park;
  final String location;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 40), // balances the gear on the right
            const Expanded(
              child: Center(
                child: _WordmarkAndLive(),
              ),
            ),
            _IconButton(icon: Icons.settings_rounded, onTap: onSettings),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_on_rounded,
                color: _RadioPalette.green, size: 16),
            const SizedBox(width: 6),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(park,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _RadioPalette.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  Text(location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _RadioPalette.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WordmarkAndLive extends StatelessWidget {
  const _WordmarkAndLive();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RichText(
          text: const TextSpan(
            children: [
              TextSpan(
                  text: 'ExplorerOS ',
                  style: TextStyle(
                      color: _RadioPalette.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
              TextSpan(
                  text: 'Radio',
                  style: TextStyle(
                      color: _RadioPalette.green,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        const _LiveBadge(),
      ],
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _RadioPalette.green,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text('LIVE',
          style: TextStyle(
              color: Colors.black,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5)),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: _RadioPalette.textSecondary, size: 24),
        ),
      ),
    );
  }
}

// ── Scenic panoramic card ───────────────────────────────────────────────────

class _ScenicCard extends StatelessWidget {
  const _ScenicCard({
    required this.imageUrl,
    required this.location,
    this.landmark,
    this.glowing = false,
  });

  final String? imageUrl;
  final String location;
  final String? landmark;
  final bool glowing;

  @override
  Widget build(BuildContext context) {
    final h = (MediaQuery.of(context).size.height * 0.22).clamp(120.0, 190.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(_RadioPalette.radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_RadioPalette.radius),
          border: glowing
              ? Border.all(color: _RadioPalette.green, width: 2)
              : null,
        ),
        child: SizedBox(
          height: h,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
                child: (imageUrl != null && imageUrl!.isNotEmpty)
                    ? Image.network(imageUrl!,
                        key: ValueKey(imageUrl), fit: BoxFit.cover)
                    : const ColoredBox(
                        key: ValueKey('placeholder'),
                        color: _RadioPalette.panel),
              ),
              // Legibility gradient.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xCC000000)],
                    stops: [0.45, 1],
                  ),
                ),
              ),
              Positioned(
                left: 14,
                bottom: 12,
                child: _OverlayChip(
                  icon: Icons.wb_sunny_rounded,
                  label: '72°F',
                ),
              ),
              if (landmark != null)
                Positioned(
                  right: 14,
                  bottom: 12,
                  child: _OverlayChip(
                    icon: Icons.near_me_rounded,
                    label: 'Near ${_shorten(landmark!)}',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _shorten(String s) => s.length <= 22 ? s : '${s.substring(0, 21)}…';
}

class _OverlayChip extends StatelessWidget {
  const _OverlayChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Now Playing card ────────────────────────────────────────────────────────

/// The "What's Near Me?" picker: nearby places within ~20 miles. Tapping one
/// plays it as a temporary report, then the radio resumes where it paused.
class _NearbyListSheet extends ConsumerWidget {
  const _NearbyListSheet({required this.onPick});
  final void Function(MasterLocation) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(nearbyReportOptionsProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: _RadioPalette.panelAlt,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Row(children: [
              Text('📍 ', style: TextStyle(fontSize: 16)),
              Text("What's Near Me",
                  style: TextStyle(
                      color: _RadioPalette.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 2),
            const Text('Tap a place to hear about it, then back to the radio.',
                style:
                    TextStyle(color: _RadioPalette.textSecondary, fontSize: 12)),
            const SizedBox(height: 12),
            if (options.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text('Getting your location…',
                      style: TextStyle(color: _RadioPalette.textSecondary)),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.55),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: options.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: _RadioPalette.panelAlt),
                  itemBuilder: (_, i) {
                    final o = options[i];
                    final l = o.location;
                    final miles = o.distanceMeters / 1609.344;
                    return ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      leading: Icon(
                        l.isReady
                            ? Icons.volume_up_rounded
                            : Icons.mic_none_rounded,
                        color: l.isReady
                            ? _RadioPalette.green
                            : _RadioPalette.textSecondary,
                      ),
                      title: Text(l.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: _RadioPalette.textPrimary,
                              fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${l.type.label} · ${miles.toStringAsFixed(miles < 10 ? 1 : 0)} mi',
                        style: const TextStyle(
                            color: _RadioPalette.textSecondary, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.play_circle_fill_rounded,
                          color: _RadioPalette.green),
                      onTap: () => onPick(l),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The station/report indicator: 🎵 ExplorerOS Radio normally, or 👁 / 📍 while
/// a temporary report is on air. Switches back automatically when it ends.
class _LiveIndicator extends StatelessWidget {
  const _LiveIndicator({required this.interruption});
  final _Interruption interruption;

  @override
  Widget build(BuildContext context) {
    final active = interruption != _Interruption.none;
    final color = interruption.color;
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: active ? 0.20 : 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(interruption.emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Text(
              interruption.label,
              style: TextStyle(
                color: active ? color : _RadioPalette.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
            if (active) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('LIVE',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({
    required this.title,
    required this.host,
    required this.playing,
    this.subtitle,
    this.onBackToRadio,
  });

  final String title;
  final String host;
  final bool playing;
  final String? subtitle;
  final VoidCallback? onBackToRadio;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: _RadioPalette.panel,
        borderRadius: BorderRadius.circular(_RadioPalette.radius),
        border: Border.all(color: _RadioPalette.panelAlt),
      ),
      child: Column(
        children: [
          const Text('NOW PLAYING',
              style: TextStyle(
                  color: _RadioPalette.green,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2)),
          const SizedBox(height: 10),
          Text(title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: _RadioPalette.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  height: 1.15)),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle!,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: _RadioPalette.textSecondary,
                    fontStyle: FontStyle.italic,
                    fontSize: 13)),
          ],
          const SizedBox(height: 14),
          _Waveform(active: playing),
          const SizedBox(height: 14),
          RichText(
            text: TextSpan(
              children: [
                const TextSpan(
                    text: 'Hosted by ',
                    style: TextStyle(
                        color: _RadioPalette.textSecondary, fontSize: 14)),
                TextSpan(
                    text: host,
                    style: const TextStyle(
                        color: _RadioPalette.green,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontStyle: FontStyle.italic)),
              ],
            ),
          ),
          if (onBackToRadio != null) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: onBackToRadio,
              icon: const Icon(Icons.radio_rounded,
                  color: _RadioPalette.green, size: 18),
              label: const Text('Back to radio',
                  style: TextStyle(color: _RadioPalette.green)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Subtle broadcast waveform; animates only while audio is playing.
class _Waveform extends StatefulWidget {
  const _Waveform({required this.active});
  final bool active;

  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));

  static const int _bars = 21;
  // Stable per-bar heights so the waveform looks organic (not uniform).
  static final List<double> _seed = () {
    final rng = Random(7);
    return [for (var i = 0; i < _bars; i++) 0.35 + 0.65 * rng.nextDouble()];
  }();

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _Waveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < _bars; i++) _bar(i),
            ],
          );
        },
      ),
    );
  }

  Widget _bar(int i) {
    final base = _seed[i.clamp(0, _seed.length - 1)];
    // When idle, show a low, flat centerline; when playing, animate around base.
    final phase = ((_c.value + i * 0.12) % 1.0);
    final wobble = widget.active ? (phase < 0.5 ? phase : 1 - phase) : 0.06;
    final height = (6 + (base * 22) * (0.4 + wobble)).clamp(4.0, 32.0);
    // Center bars slightly brighter for a focal point.
    final mid = (i - _bars / 2).abs() / (_bars / 2);
    final color = Color.lerp(
        _RadioPalette.green, _RadioPalette.greenSoft, mid.clamp(0, 1))!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(
        width: 3,
        height: height,
        decoration: BoxDecoration(
          color: widget.active
              ? color
              : _RadioPalette.greenSoft.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

// ── Playback controls ───────────────────────────────────────────────────────

class _Controls extends StatelessWidget {
  const _Controls({
    required this.isPlaying,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
  });

  final bool isPlaying;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _SecondaryControl(icon: Icons.skip_previous_rounded, onTap: onPrevious),
        const SizedBox(width: 28),
        _PlayButton(isPlaying: isPlaying, onTap: onPlayPause),
        const SizedBox(width: 28),
        _SecondaryControl(icon: Icons.skip_next_rounded, onTap: onNext),
      ],
    );
  }
}

class _SecondaryControl extends StatelessWidget {
  const _SecondaryControl({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _RadioPalette.panel,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Icon(icon, color: _RadioPalette.textPrimary, size: 30),
        ),
      ),
    );
  }
}

/// The largest control on screen; press animation + green glow.
class _PlayButton extends StatefulWidget {
  const _PlayButton({required this.isPlaying, required this.onTap});
  final bool isPlaying;
  final VoidCallback onTap;

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.92 : 1,
        duration: const Duration(milliseconds: 110),
        child: Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: _RadioPalette.green,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _RadioPalette.green.withValues(alpha: 0.45),
                blurRadius: 28,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(
            widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.black,
            size: 46,
          ),
        ),
      ),
    );
  }
}

// ── Primary actions ─────────────────────────────────────────────────────────

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.tint = _RadioPalette.green,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _RadioPalette.panel,
      borderRadius: BorderRadius.circular(_RadioPalette.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(_RadioPalette.radius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_RadioPalette.radius),
            border: Border.all(color: tint.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: tint, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: _RadioPalette.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(description,
                        style: const TextStyle(
                            color: _RadioPalette.textSecondary,
                            fontSize: 12.5,
                            height: 1.25)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded,
                  color: _RadioPalette.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Coming up next ──────────────────────────────────────────────────────────

class _ComingUpNext extends StatelessWidget {
  const _ComingUpNext({required this.items});
  final List<PlaybackQueueItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _RadioPalette.panel,
        borderRadius: BorderRadius.circular(_RadioPalette.radius),
        border: Border.all(color: _RadioPalette.panelAlt),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('COMING UP NEXT',
              style: TextStyle(
                  color: _RadioPalette.green,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5)),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Nothing queued yet',
                  style: TextStyle(color: _RadioPalette.textSecondary)),
            )
          else
            for (var i = 0; i < items.length; i++) ...[
              _row(items[i]),
              if (i != items.length - 1)
                const Divider(color: _RadioPalette.panelAlt, height: 18),
            ],
        ],
      ),
    );
  }

  Widget _row(PlaybackQueueItem item) {
    final seg = item.segment;
    return Row(
      children: [
        const _MiniWave(),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(seg.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: _RadioPalette.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              const Text('Hosted by $_stationHost',
                  style: TextStyle(
                      color: _RadioPalette.textSecondary, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text('${_estMinutes(seg)} min',
            style: const TextStyle(
                color: _RadioPalette.textSecondary, fontSize: 12)),
      ],
    );
  }

  /// A light estimate of how long an item runs (used as the "up next" time).
  /// Uses the real duration when known, else a sensible default by content.
  static int _estMinutes(AudioSegment seg) {
    final secs = seg.duration.inSeconds;
    if (secs > 0) return (secs / 60).ceil().clamp(1, 99);
    return seg.type == AudioSegmentType.music ? 3 : 2;
  }
}

/// A small static three-bar glyph for queued items.
class _MiniWave extends StatelessWidget {
  const _MiniWave();

  @override
  Widget build(BuildContext context) {
    const heights = [10.0, 18.0, 8.0, 14.0];
    return SizedBox(
      width: 28,
      height: 22,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final h in heights)
            Container(
              width: 3,
              height: h,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: _RadioPalette.green,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}
