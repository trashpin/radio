import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:explorer_os_mobile/core/error/app_exception.dart';
import 'package:explorer_os_mobile/core/error/error_handler.dart';
import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/gps/providers/gps_status_provider.dart';
import 'package:explorer_os_mobile/features/locations/data/location_favorites.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/location_engine.dart';
import 'package:explorer_os_mobile/features/locations/presentation/destination_detail_card.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';
import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/discovery/nearby_narration_controller.dart';
import 'package:explorer_os_mobile/features/radio/discovery/observation_controller.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_state.dart';
import 'package:explorer_os_mobile/features/radio/presentation/stations_screen.dart';
import 'package:explorer_os_mobile/features/radio/providers/radio_session_provider.dart';
import 'package:explorer_os_mobile/features/radio/widgets/now_playing.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_brand_header.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';
import 'package:explorer_os_mobile/features/weather/current_weather.dart';
import 'package:explorer_os_mobile/shared/models/radio_station.dart';

/// The content currently on air during a live report — drives the Now Playing
/// hero (images/title/category/distance + favorite/navigate/photos wiring).
class _NowPlayingContent {
  const _NowPlayingContent({
    required this.title,
    required this.category,
    required this.images,
    this.distanceLabel,
    this.locationId,
    this.latitude,
    this.longitude,
  });
  final String title;
  final String category;
  final List<String> images;
  final String? distanceLabel;
  final String? locationId; // favorites (locations only)
  final double? latitude;
  final double? longitude;

  bool get canNavigate => latitude != null && longitude != null;
  bool get canFavorite => locationId != null;
  bool get hasGallery => images.length > 1;
}

/// Friendly category label for a species `category` token.
String _speciesCategoryLabel(String token) {
  switch (token.toLowerCase()) {
    case 'animals':
      return 'Wildlife';
    case 'birds':
      return 'Birds';
    case 'plants':
      return 'Plants';
    case 'trees':
      return 'Trees';
    case 'wildflowers':
      return 'Flowers';
    case 'fish':
      return 'Fish';
    case 'reptiles':
      return 'Reptiles';
    case 'amphibians':
      return 'Amphibians';
    default:
      return 'Nature';
  }
}

/// Resolves a species hero image (full URL, or a relative `media` storage path).
String? _resolveSpeciesImage(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  if (raw.startsWith('http')) return raw;
  try {
    return SupabaseService.client.storage.from('media').getPublicUrl(raw);
  } catch (_) {
    return null;
  }
}

/// A UI label for the on-air host (the interface never exposes internal content
/// types — only what's playing and who hosts it).
const String _stationHost = 'Ranger Jake';

/// The ExplorerOS Radio player — a premium automotive-infotainment layout that
/// recreates the reference design with reusable widgets + the design system.
class RadioScreen extends ConsumerWidget {
  const RadioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(radioSessionProvider);
    return Scaffold(
      backgroundColor: RD.bg,
      body: session.when(
        loading: () => const _Message(message: 'Tuning in…', spinner: true),
        error: (error, stack) {
          final e = error is AppException ? error : ErrorHandler.from(error, stack);
          return _Message(
            message: e.message,
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

class _Message extends StatelessWidget {
  const _Message({required this.message, this.spinner = false, this.onRetry});
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
              const CircularProgressIndicator(color: RD.green),
              const SizedBox(height: 20),
            ],
            Text(message, textAlign: TextAlign.center, style: RD.body),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              TextButton(
                onPressed: onRetry,
                child: const Text('Try again',
                    style: TextStyle(color: RD.green)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Which temporary live "report" is interrupting the station (if any).
enum _Interruption { none, iSeeSomething, whatsNearMe }

class _Player extends ConsumerStatefulWidget {
  const _Player({required this.station});
  final RadioStation station;

  @override
  ConsumerState<_Player> createState() => _PlayerState();
}

class _PlayerState extends ConsumerState<_Player> {
  @override
  void initState() {
    super.initState();
    // Begin acquiring GPS so Nearby Stories / weather populate.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gpsStatusProvider.notifier).requestAndStart();
    });
  }

  void _maybeRefreshWeather() {
    final center = ref.read(mapCenterProvider);
    if (center == null) return;
    ref
        .read(currentWeatherProvider.notifier)
        .refresh(center.latitude, center.longitude);
  }

  @override
  Widget build(BuildContext context) {
    final playback = ref.watch(radioEngineControllerProvider);
    final controller = ref.read(radioEngineControllerProvider.notifier);
    final obs = ref.watch(observationControllerProvider);
    final nearby = ref.watch(nearbyNarrationControllerProvider);
    final nearbyStories = ref.watch(nearbyLocationsProvider);
    final weather = ref.watch(currentWeatherProvider);
    final isPlaying = playback.status == PlaybackStatus.playing;

    // Refresh weather once a GPS fix flows into the map center.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRefreshWeather());

    final interruption = (obs.active && obs.narrating)
        ? _Interruption.iSeeSomething
        : (nearby.active && nearby.narrating
            ? _Interruption.whatsNearMe
            : _Interruption.none);

    // What's on air right now (never the internal category).
    final nowPlaying = playback.current?.segment;
    final title = switch (interruption) {
      _Interruption.iSeeSomething => obs.species!.commonName,
      _Interruption.whatsNearMe => nearby.location?.name ?? 'Nearby',
      _Interruption.none => (nowPlaying?.title.trim().isNotEmpty ?? false)
          ? nowPlaying!.title
          : 'ExplorerOS Radio',
    };
    final onAir = isPlaying ||
        (obs.active && obs.narrating) ||
        (nearby.active && nearby.narrating);

    // Nearest place → hero art + NEARBY badge.
    final nearest = nearbyStories.isEmpty ? null : nearbyStories.first;
    final heroImage = obs.species?.heroImageUrl ??
        (nearest?.location.images.isNotEmpty ?? false
            ? nearest!.location.images.first
            : widget.station.imageUrl);
    final nearbyPlace = nearest?.location.name ?? widget.station.name;
    final nearbyDistance =
        nearest == null ? null : _miles(nearest.distanceMeters);

    void backToRadio() {
      if (obs.active) ref.read(observationControllerProvider.notifier).clear();
      if (nearby.active) {
        ref.read(nearbyNarrationControllerProvider.notifier).clear();
      }
    }

    // The item currently on air (if any) → drives the expanded Now Playing hero.
    final np = _nowPlayingContent(interruption, obs, nearby, nearbyStories);
    final expanded = np != null;
    final favorites = ref.watch(locationFavoritesProvider);
    final isFav = np?.locationId != null && favorites.contains(np!.locationId);

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(RD.lg, RD.sm, RD.lg, RD.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RadioBrandHeader(
              onMenu: _openMenu,
              onNotifications: () => _snack('No new notifications'),
            ),
            const SizedBox(height: RD.lg),
            // The player transforms into a "Now Playing" experience whenever a
            // story/song/report is on air, then collapses back automatically.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(
                          begin: const Offset(0, 0.05), end: Offset.zero)
                      .animate(anim),
                  child: child,
                ),
              ),
              child: expanded
                  ? _NowPlayingView(
                      key: const ValueKey('now-playing'),
                      content: np,
                      isPlaying: isPlaying,
                      isFavorite: isFav,
                      onPlayPause:
                          isPlaying ? controller.pause : controller.play,
                      onSkip: controller.skip,
                      onFavorite: np.canFavorite
                          ? () => ref
                              .read(locationFavoritesProvider.notifier)
                              .toggle(np.locationId!)
                          : null,
                      onNavigate: np.canNavigate
                          ? () => _navigate(np.latitude!, np.longitude!)
                          : null,
                      onMorePhotos: np.hasGallery
                          ? () => showRadioPhotoGallery(
                              context, np.images, np.title)
                          : null,
                      onBackToRadio: backToRadio,
                    )
                  : Column(
                      key: const ValueKey('radio'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Hero(
                          imageUrl: heroImage,
                          place: nearbyPlace,
                          distanceLabel: nearbyDistance,
                          onAir: onAir,
                        ),
                        const SizedBox(height: RD.lg),
                        _NowPlayingLine(title: title),
                        const SizedBox(height: RD.md),
                        _TransportRow(
                          isPlaying: isPlaying,
                          onPlayPause:
                              isPlaying ? controller.pause : controller.play,
                          onPrevious: controller.previous,
                          onNext: controller.skip,
                          active: onAir,
                        ),
                        const SizedBox(height: RD.xl),
                        PrimaryActionCard(
                          icon: Icons.visibility_rounded,
                          title: 'I SEE SOMETHING',
                          subtitle:
                              'Discover wildlife, landmarks and hidden gems',
                          onTap: () =>
                              context.push(AppRoute.iSeeSomething.path),
                        ),
                        const SizedBox(height: RD.md),
                        PrimaryActionCard(
                          icon: Icons.diamond_rounded,
                          title: 'LOCAL GEMS',
                          subtitle:
                              'Find great places to eat, drink & explore nearby',
                          onTap: () => context.push(AppRoute.localGems.path),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: RD.xl),
            _NearbyStories(
              stories: nearbyStories.take(8).toList(),
              onViewMap: () => context.go(AppRoute.map.path),
            ),
            const SizedBox(height: RD.lg),
            _StatusBar(storyCount: nearbyStories.length, weather: weather),
          ],
        ),
      ),
    );
  }

  /// Builds the on-air content for the Now Playing hero from the active report.
  _NowPlayingContent? _nowPlayingContent(
    _Interruption interruption,
    ObservationState obs,
    NearbyNarrationState nearby,
    List<NearbyLocation> nearbyStories,
  ) {
    if (interruption == _Interruption.iSeeSomething && obs.species != null) {
      final s = obs.species!;
      final img = _resolveSpeciesImage(s.heroImageUrl);
      return _NowPlayingContent(
        title: s.commonName,
        category: _speciesCategoryLabel(s.category),
        images: [?img],
      );
    }
    if (interruption == _Interruption.whatsNearMe && nearby.location != null) {
      final l = nearby.location!;
      double? dist;
      for (final n in nearbyStories) {
        if (n.location.id == l.id) {
          dist = n.distanceMeters;
          break;
        }
      }
      return _NowPlayingContent(
        title: l.name,
        category: l.type.label,
        images: l.images,
        distanceLabel: dist == null ? null : _miles(dist),
        locationId: l.id,
        latitude: l.latitude,
        longitude: l.longitude,
      );
    }
    return null;
  }

  Future<void> _navigate(double lat, double lng) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) _snack('Could not open navigation');
  }

  static String _miles(double meters) {
    final mi = meters / 1609.344;
    return mi < 10 ? '${mi.toStringAsFixed(1)} miles away' : '${mi.round()} miles away';
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  void _openMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: RD.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(RD.rXl)),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: RD.md),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: RD.stroke, borderRadius: BorderRadius.circular(2)),
            ),
            ListTile(
              leading: const Icon(Icons.radio_rounded, color: RD.green),
              title: const Text('Change station',
                  style: TextStyle(color: RD.textPrimary)),
              onTap: () {
                Navigator.pop(sheet);
                context.push(AppRoute.stationSelect.path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.grid_view_rounded, color: RD.green),
              title: const Text('Browse stations',
                  style: TextStyle(color: RD.textPrimary)),
              onTap: () {
                Navigator.pop(sheet);
                Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const StationsScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_rounded, color: RD.green),
              title: const Text('Settings',
                  style: TextStyle(color: RD.textPrimary)),
              onTap: () {
                Navigator.pop(sheet);
                context.push(AppRoute.settings.path);
              },
            ),
            const SizedBox(height: RD.sm),
          ],
        ),
      ),
    );
  }
}

// ── Hero panel ───────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero({
    required this.imageUrl,
    required this.place,
    this.distanceLabel,
    this.onAir = false,
  });

  final String? imageUrl;
  final String place;
  final String? distanceLabel;
  final bool onAir;

  @override
  Widget build(BuildContext context) {
    final h = (MediaQuery.of(context).size.height * 0.30).clamp(190.0, 320.0);
    return ClipRRect(
      borderRadius: RD.brXl,
      child: SizedBox(
        height: h,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: RD.slow,
              child: (imageUrl != null && imageUrl!.isNotEmpty)
                  ? Image.network(imageUrl!,
                      key: ValueKey(imageUrl), fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: RD.panel))
                  : const ColoredBox(key: ValueKey('ph'), color: RD.panel),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x55000000), Colors.transparent, Color(0x66000000)],
                  stops: [0, 0.5, 1],
                ),
              ),
            ),
            Positioned(
              top: RD.md,
              left: RD.md,
              child: NearbyBadge(place: place, distanceLabel: distanceLabel),
            ),
            Positioned(
              top: RD.md,
              right: RD.md,
              child: GlassChip(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const LiveBadge(compact: true),
                  const SizedBox(width: RD.sm),
                  Equalizer(active: onAir, bars: 7, height: 18, barWidth: 2.5),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Now playing (compact, single line) ───────────────────────────────────────

class _NowPlayingLine extends StatelessWidget {
  const _NowPlayingLine({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: RD.title.copyWith(fontSize: 20)),
        const SizedBox(height: 2),
        Text('Hosted by $_stationHost',
            style: RD.caption.copyWith(color: RD.green, fontSize: 12)),
      ],
    );
  }
}

/// The expanded "Now Playing" experience shown while a story/song/report is on
/// air: a Ken Burns / slideshow hero with the item's title, category, distance
/// and favorite, plus Play/Pause, Skip, Save, Navigate and More Photos controls.
class _NowPlayingView extends StatelessWidget {
  const _NowPlayingView({
    super.key,
    required this.content,
    required this.isPlaying,
    required this.isFavorite,
    required this.onPlayPause,
    required this.onSkip,
    required this.onBackToRadio,
    this.onFavorite,
    this.onNavigate,
    this.onMorePhotos,
  });

  final _NowPlayingContent content;
  final bool isPlaying;
  final bool isFavorite;
  final VoidCallback onPlayPause;
  final VoidCallback onSkip;
  final VoidCallback onBackToRadio;
  final VoidCallback? onFavorite;
  final VoidCallback? onNavigate;
  final VoidCallback? onMorePhotos;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NowPlayingHero(
          images: content.images,
          title: content.title,
          category: content.category,
          distanceLabel: content.distanceLabel,
          favorite: content.canFavorite ? isFavorite : null,
          onFavorite: onFavorite,
        ),
        const SizedBox(height: RD.lg),
        NowPlayingControls(
          isPlaying: isPlaying,
          onPlayPause: onPlayPause,
          onSkip: onSkip,
          saved: content.canFavorite ? isFavorite : null,
          onSave: onFavorite,
          onNavigate: onNavigate,
          onMorePhotos: onMorePhotos,
        ),
        const SizedBox(height: RD.sm),
        Center(
          child: TextButton.icon(
            onPressed: onBackToRadio,
            icon: const Icon(Icons.radio_rounded, color: RD.green, size: 18),
            label: const Text('Back to radio',
                style: TextStyle(color: RD.green)),
          ),
        ),
      ],
    );
  }
}

// ── Transport row: equalizer | controls | equalizer ──────────────────────────

class _TransportRow extends StatelessWidget {
  const _TransportRow({
    required this.isPlaying,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.active,
  });

  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: Equalizer(active: active, bars: 6, height: 40, seed: 3),
          ),
        ),
        const SizedBox(width: RD.md),
        PlaybackControls(
          isPlaying: isPlaying,
          onPrevious: onPrevious,
          onPlayPause: onPlayPause,
          onNext: onNext,
        ),
        const SizedBox(width: RD.md),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Equalizer(active: active, bars: 6, height: 40, seed: 9),
          ),
        ),
      ],
    );
  }
}

// ── Nearby Stories carousel ──────────────────────────────────────────────────

class _NearbyStories extends StatefulWidget {
  const _NearbyStories({required this.stories, required this.onViewMap});
  final List<NearbyLocation> stories;
  final VoidCallback onViewMap;

  @override
  State<_NearbyStories> createState() => _NearbyStoriesState();
}

class _NearbyStoriesState extends State<_NearbyStories> {
  final _controller = PageController(viewportFraction: 0.62);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stories = widget.stories;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('NEARBY STORIES', style: RD.sectionLabel),
            const Spacer(),
            InkWell(
              onTap: widget.onViewMap,
              borderRadius: BorderRadius.circular(RD.rSm),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: RD.xs, vertical: 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('VIEW MAP',
                      style: RD.sectionLabel.copyWith(fontSize: 12)),
                  const SizedBox(width: 4),
                  const Icon(Icons.location_on_rounded,
                      color: RD.green, size: 15),
                ]),
              ),
            ),
          ],
        ),
        const SizedBox(height: RD.md),
        if (stories.isEmpty)
          GlassPanel(
            child: Row(children: [
              const Icon(Icons.explore_rounded, color: RD.green),
              const SizedBox(width: RD.md),
              Expanded(
                child: Text(
                  'Finding stories around you… make sure location is on.',
                  style: RD.body,
                ),
              ),
            ]),
          )
        else ...[
          SizedBox(
            height: 168,
            child: PageView.builder(
              controller: _controller,
              padEnds: false,
              onPageChanged: (i) => setState(() => _page = i),
              itemCount: stories.length,
              itemBuilder: (_, i) {
                final s = stories[i];
                final mi = s.distanceMeters / 1609.344;
                return Padding(
                  padding: const EdgeInsets.only(right: RD.md),
                  child: StoryCard(
                    width: double.infinity,
                    title: s.location.name,
                    category: s.location.type.label,
                    imageUrl: s.location.images.isNotEmpty
                        ? s.location.images.first
                        : null,
                    distanceLabel:
                        '${mi.toStringAsFixed(mi < 10 ? 1 : 0)} mi',
                    onTap: () => showDestinationDetail(context, s.location,
                        distanceMeters: s.distanceMeters),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: RD.md),
          PageDots(count: stories.length.clamp(1, 8), index: _page.clamp(0, 7)),
        ],
      ],
    );
  }
}

// ── Bottom status bar ────────────────────────────────────────────────────────

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.storyCount, required this.weather});
  final int storyCount;
  final dynamic weather; // WeatherData?

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final temp = weather?.temperatureF ?? weather?.highF;
    final condition = (weather?.condition ?? '').toString();
    return StatusBar(
      segments: [
        StatusSegment(
          icon: Icons.location_on_rounded,
          value: '$storyCount stories',
          label: 'Nearby · keep exploring!',
        ),
        StatusSegment(
          icon: Icons.wb_sunny_rounded,
          tint: RD.amber,
          value: temp == null ? '—' : '${temp.round()}°F',
          label: condition.isEmpty ? 'Weather' : condition,
        ),
        StatusSegment(
          icon: Icons.schedule_rounded,
          value: _time(now),
          label: _date(now),
        ),
      ],
    );
  }

  static String _time(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  static String _date(DateTime d) =>
      '${_days[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';
}
