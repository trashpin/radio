import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:explorer_os_mobile/core/error/app_exception.dart';
import 'package:explorer_os_mobile/core/error/error_handler.dart';
import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/gps/presentation/location_prompt.dart';
import 'package:explorer_os_mobile/features/gps/providers/gps_status_provider.dart';
import 'package:explorer_os_mobile/features/locations/data/location_favorites.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/location_engine.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';
import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/discovery/gem_narration_controller.dart';
import 'package:explorer_os_mobile/features/radio/discovery/nearby_narration_controller.dart';
import 'package:explorer_os_mobile/features/radio/discovery/observation_controller.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_state.dart';
import 'package:explorer_os_mobile/features/radio/presentation/stations_screen.dart';
import 'package:explorer_os_mobile/features/radio/providers/explore_providers.dart';
import 'package:explorer_os_mobile/features/radio/providers/radio_session_provider.dart';
import 'package:explorer_os_mobile/features/radio/services/player_location_context.dart';
import 'package:explorer_os_mobile/features/radio/services/tell_me_more_mapping.dart';
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
          final e = error is AppException
              ? error
              : ErrorHandler.from(error, stack);
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
                child: const Text(
                  'Try again',
                  style: TextStyle(color: RD.green),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Which temporary live "report" is interrupting the station (if any).
enum _Interruption { none, iSeeSomething, whatsNearMe, gem }

class _Player extends ConsumerStatefulWidget {
  const _Player({required this.station});
  final RadioStation station;

  @override
  ConsumerState<_Player> createState() => _PlayerState();
}

class _PlayerState extends ConsumerState<_Player> {
  /// The last real "what's currently playing" image (Explore's current
  /// subject, the DJ's specific topic, or song cover art) — held over during
  /// DJ Sunny's own imageless connective lines so the display doesn't flash
  /// to a generic GPS-derived image mid-transition. See `build()`'s
  /// `heroImage` computation.
  String? _lastContentImage;

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
    final gem = ref.watch(gemNarrationControllerProvider);
    final nearbyStories = ref.watch(nearbyLocationsProvider);
    final weather = ref.watch(currentWeatherProvider);
    final isPlaying = playback.status == PlaybackStatus.playing;

    // EVENT > PARK > SPRING > TOWN > COUNTY — the location-aware player's
    // visual/info layer. Purely additive: music keeps playing regardless of
    // what this resolves to; only pressing TELL ME MORE plays anything.
    final playerCtx = ref.watch(playerLocationContextProvider);

    // Refresh weather once a GPS fix flows into the map center.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRefreshWeather());

    final interruption = (obs.active && obs.narrating)
        ? _Interruption.iSeeSomething
        : (nearby.active && nearby.narrating
              ? _Interruption.whatsNearMe
              : (gem.active && gem.narrating
                    ? _Interruption.gem
                    : _Interruption.none));

    // What's on air right now (never the internal category).
    final nowPlaying = playback.current?.segment;

    // What the DJ is CURRENTLY TALKING ABOUT — distinct from the GPS-based
    // playerCtx above. A DJ banter/narration segment already carries a
    // TellMeMoreContext with whatever destination/location it's scoped to
    // (dj_banter_scheduler.dart); tellMeMoreResultProvider resolves that
    // into a title + image the same way TELL ME MORE itself would, so the
    // two can never disagree. Null while music/generic banter (no specific
    // subject) is on air, or before the async lookup resolves.
    final djCtx = nowPlaying?.tellMeMoreContext;
    final djTopic = (djCtx != null && djCtx.hasContext)
        ? ref.watch(tellMeMoreResultProvider(djCtx)).value
        : null;

    // MARION COUNTY EXPLORE's own current subject — image, name, and
    // NAVIGATE target are all carried directly on the segment itself (set at
    // candidate-build time in explore_providers.dart), not re-resolved
    // through a second async lookup, so they can never drift from what's
    // actually narrating (spec: "current subject").
    final exploreSegment =
        (nowPlaying?.tags.contains('explore') ?? false) ? nowPlaying : null;

    final title = switch (interruption) {
      _Interruption.iSeeSomething => obs.species!.commonName,
      _Interruption.whatsNearMe => nearby.location?.name ?? 'Nearby',
      _Interruption.gem => gem.gem?.name ?? 'Local Gem',
      _Interruption.none =>
        (nowPlaying?.title.trim().isNotEmpty ?? false)
            ? nowPlaying!.title
            : 'Sunshine Travel Radio',
    };
    final onAir =
        isPlaying ||
        (obs.active && obs.narrating) ||
        (nearby.active && nearby.narrating) ||
        (gem.active && gem.narrating);

    // A song's cover art takes over the display while music is playing.
    final songCover = nowPlaying?.type == AudioSegmentType.music
        ? nowPlaying?.imageUrl
        : null;
    final songArtist = nowPlaying?.type == AudioSegmentType.music
        ? (nowPlaying?.artist ?? '').trim()
        : '';

    // Nearest place → hero art + NEARBY badge.
    final nearest = nearbyStories.isEmpty ? null : nearbyStories.first;
    // What's actually being narrated/played right now, in its own words: the
    // currently-playing segment's own image (Explore's current subject, or
    // what the DJ is specifically talking about, or — for a song — its own
    // cover art). GPS is WHERE the traveler is; this is WHAT is on air —
    // the two are independent and this must win whenever it has an answer.
    final contentImage = (exploreSegment?.imageUrl ?? '').isNotEmpty
        ? exploreSegment!.imageUrl!
        : ((djTopic?.imageUrl ?? '').isNotEmpty
            ? djTopic!.imageUrl!
            : ((songCover ?? '').isNotEmpty ? songCover! : ''));
    // DJ Sunny's own connective lines (block openers/transitions/station IDs)
    // carry no image of their own — they're not "about" anything with a
    // photo, just glue between two real pieces of content. Rather than the
    // display falling back to a generic GPS/county image mid-transition (a
    // visible flicker away from what was just shown), hold the last real
    // content image until the next segment with one of its own takes over.
    if (contentImage.isNotEmpty) _lastContentImage = contentImage;
    // Priority: the current segment's own content image > the last real
    // content image (held through an imageless DJ transition) > the
    // GPS-based event/park/spring/town/county context > generic fallbacks.
    // The music itself is unaffected either way — only what's displayed
    // changes.
    final heroImage =
        obs.species?.heroImageUrl ??
        (contentImage.isNotEmpty
            ? contentImage
            : (((_lastContentImage ?? '')).isNotEmpty
                  ? _lastContentImage
                  : ((playerCtx?.imageUrl ?? '').isNotEmpty
                        ? playerCtx!.imageUrl
                        : (nearest?.location.images.isNotEmpty ?? false
                              ? nearest!.location.images.first
                              : widget.station.imageUrl))));
    final nearbyPlace = exploreSegment?.title ??
        djTopic?.title ??
        playerCtx?.title ??
        nearest?.location.name ??
        widget.station.name;
    final nearbyDistance = (exploreSegment != null || djTopic != null)
        ? null
        : (playerCtx?.distanceLabel ??
            (nearest == null ? null : _miles(nearest.distanceMeters)));

    void backToRadio() {
      if (obs.active) ref.read(observationControllerProvider.notifier).clear();
      if (nearby.active) {
        ref.read(nearbyNarrationControllerProvider.notifier).clear();
      }
      if (gem.active) {
        ref.read(gemNarrationControllerProvider.notifier).clear();
      }
    }

    // The item currently on air (if any) → drives the expanded Now Playing hero.
    final np = _nowPlayingContent(
      interruption,
      obs,
      nearby,
      gem,
      nearbyStories,
    );
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
            const SizedBox(height: RD.md),
            const _ExploreModeToggle(),
            const SizedBox(height: RD.sm),
            // Actionable prompt when there's no location yet — hides itself the
            // moment a GPS fix arrives (otherwise the nearby list sits empty).
            const LocationPrompt(margin: EdgeInsets.only(bottom: RD.md)),
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
                    begin: const Offset(0, 0.05),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: expanded
                  ? _NowPlayingView(
                      key: const ValueKey('now-playing'),
                      content: np,
                      isPlaying: isPlaying,
                      isFavorite: isFav,
                      onPlayPause: isPlaying
                          ? controller.pause
                          : controller.play,
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
                              context,
                              np.images,
                              np.title,
                            )
                          : null,
                      onBackToRadio: backToRadio,
                    )
                  : Column(
                      key: const ValueKey('radio'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (ref.watch(exploreActiveProvider)) ...[
                          const _ExploreBanner(),
                          const SizedBox(height: RD.sm),
                        ],
                        _Hero(
                          imageUrl: heroImage,
                          place: nearbyPlace,
                          distanceLabel: nearbyDistance,
                          onAir: onAir,
                        ),
                        const SizedBox(height: RD.lg),
                        _NowPlayingLine(
                          title: title,
                          subtitle: songArtist.isNotEmpty
                              ? songArtist
                              : 'Hosted by $_stationHost',
                        ),
                        if ((playerCtx?.teaser ?? '').isNotEmpty) ...[
                          const SizedBox(height: RD.sm),
                          _LocationTeaser(text: playerCtx!.teaser!),
                        ],
                        // MARION COUNTY EXPLORE's NAVIGATE action — shown only
                        // when the current subject is genuinely tied to a
                        // physical destination (exploreSegment.location is
                        // null for county-wide/non-geo content, so no button
                        // appears there — spec section 7/8).
                        if (exploreSegment?.location != null) ...[
                          const SizedBox(height: RD.md),
                          _NavigateButton(
                            onTap: () => _navigate(
                              exploreSegment!.location!.latitude,
                              exploreSegment.location!.longitude,
                            ),
                          ),
                        ],
                        const SizedBox(height: RD.md),
                        _TransportRow(
                          isPlaying: isPlaying,
                          onPlayPause: isPlaying
                              ? controller.pause
                              : controller.play,
                          onPrevious: controller.previous,
                          onNext: controller.skip,
                          active: onAir,
                        ),
                        const SizedBox(height: RD.xl),
                        // DISCOVER: gems, events, parks & springs,
                        // attractions/historical sites, towns, and county —
                        // reusing the exact same nearby providers and
                        // TellMeMoreContext builders as the player's own
                        // image/teaser — tapping one opens the same info page
                        // ("TELL ME MORE") for that exact place.
                        PrimaryActionCard(
                          icon: Icons.explore_rounded,
                          title: 'DISCOVER',
                          subtitle:
                              'Gems, events, parks, springs & attractions nearby',
                          onTap: () => context.push(AppRoute.nearbyPlaces.path),
                        ),
                      ],
                    ),
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
    GemNarrationState gemState,
    List<NearbyLocation> nearbyStories,
  ) {
    if (interruption == _Interruption.gem && gemState.gem != null) {
      final g = gemState.gem!;
      final images = <String>[
        if ((g.featuredImage ?? '').isNotEmpty) g.featuredImage!,
        ...g.galleryImages.where((u) => u != g.featuredImage),
      ];
      return _NowPlayingContent(
        title: g.name,
        category: (g.category ?? '').isNotEmpty ? g.category! : 'Local Gem',
        images: images,
        // Gems keep the Navigate button visible during playback when we have
        // coordinates; they aren't part of the locations favorites list.
        latitude: g.hasCoordinates ? g.latitude : null,
        longitude: g.hasCoordinates ? g.longitude : null,
      );
    }
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
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) _snack('Could not open navigation');
  }

  static String _miles(double meters) {
    final mi = meters / 1609.344;
    return mi < 10
        ? '${mi.toStringAsFixed(1)} miles away'
        : '${mi.round()} miles away';
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

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
                color: RD.stroke,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.radio_rounded, color: RD.green),
              title: const Text(
                'Change station',
                style: TextStyle(color: RD.textPrimary),
              ),
              onTap: () {
                Navigator.pop(sheet);
                context.push(AppRoute.stationSelect.path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.grid_view_rounded, color: RD.green),
              title: const Text(
                'Browse stations',
                style: TextStyle(color: RD.textPrimary),
              ),
              onTap: () {
                Navigator.pop(sheet);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const StationsScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.explore_rounded, color: RD.green),
              title: const Text(
                'Discover this area',
                style: TextStyle(color: RD.textPrimary),
              ),
              onTap: () {
                Navigator.pop(sheet);
                context.push(AppRoute.discoverArea.path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_rounded, color: RD.green),
              title: const Text(
                'Settings',
                style: TextStyle(color: RD.textPrimary),
              ),
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
                  ? Image.network(
                      imageUrl!,
                      key: ValueKey(imageUrl),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: RD.panel),
                    )
                  : const ColoredBox(key: ValueKey('ph'), color: RD.panel),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x55000000),
                    Colors.transparent,
                    Color(0x66000000),
                  ],
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const LiveBadge(compact: true),
                    const SizedBox(width: RD.sm),
                    Equalizer(
                      active: onAir,
                      bars: 7,
                      height: 18,
                      barWidth: 2.5,
                    ),
                  ],
                ),
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
  const _NowPlayingLine({required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: RD.title.copyWith(fontSize: 20),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle ?? 'Hosted by $_stationHost',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: RD.caption.copyWith(color: RD.green, fontSize: 12),
        ),
      ],
    );
  }
}

// ── Location-aware teaser ("Did you know…") ──────────────────────────────────

/// The short curiosity-hook line for the active event/park/spring/town/county
/// tier — never the full story (that's what TELL ME MORE is for).
class _LocationTeaser extends StatelessWidget {
  const _LocationTeaser({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RD.lg),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: RD.caption.copyWith(
          color: RD.textSecondary,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

/// NAVIGATE — Explore's most important action when the current subject is a
/// physical destination (spec section 8). Opens the existing navigation
/// implementation ([_PlayerState._navigate], the same Google Maps deep link
/// every other Navigate button in this app already uses) — no second
/// navigation system.
class _NavigateButton extends StatelessWidget {
  const _NavigateButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: RD.green,
          foregroundColor: RD.onGreen,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RD.rPill)),
        ),
        icon: const Icon(Icons.navigation_rounded, size: 20),
        label: const Text('NAVIGATE', style: TextStyle(letterSpacing: 1)),
      ),
    );
  }
}

// ── Marion County Explore ─────────────────────────────────────────────────

/// RADIO / EXPLORE segmented switch. Explore is Marion-County-only for this
/// first phase: outside Marion the switch stays visible but explains why it's
/// paused rather than pretending to work (spec section 1) — the toggle itself
/// isn't disabled so a traveler already mid-drive-into-Marion can pre-select
/// it and have it engage the moment they cross the county line.
class _ExploreModeToggle extends ConsumerWidget {
  const _ExploreModeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wantsExplore = ref.watch(exploreModeProvider);
    final inMarion = ref.watch(marionCountyActiveProvider);

    Widget segment(String label, bool selected, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: RD.fast,
            padding: const EdgeInsets.symmetric(vertical: RD.sm),
            decoration: BoxDecoration(
              color: selected ? RD.green : Colors.transparent,
              borderRadius: BorderRadius.circular(RD.rPill),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: RD.badge.copyWith(
                color: selected ? RD.onGreen : RD.textSecondary,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: RD.panel,
            borderRadius: BorderRadius.circular(RD.rPill),
            border: Border.all(color: RD.stroke),
          ),
          child: Row(
            children: [
              segment(
                'RADIO',
                !wantsExplore,
                () => ref.read(exploreModeProvider.notifier).set(false),
              ),
              segment(
                'MARION COUNTY EXPLORE',
                wantsExplore,
                () => ref.read(exploreModeProvider.notifier).set(true),
              ),
            ],
          ),
        ),
        if (wantsExplore && !inMarion) ...[
          const SizedBox(height: RD.xs),
          Text(
            "Explore is paused — it starts once you're in Marion County.",
            textAlign: TextAlign.center,
            style: RD.caption.copyWith(color: RD.textFaint, fontSize: 11),
          ),
        ],
      ],
    );
  }
}

/// Shown above the hero whenever Explore is actively driving the player
/// (toggle on AND inside Marion County) — makes it unmistakable that this
/// isn't normal Radio mode (spec section 13).
class _ExploreBanner extends StatelessWidget {
  const _ExploreBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: RD.md, vertical: RD.xs),
      decoration: BoxDecoration(
        color: RD.green.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(RD.rPill),
        border: Border.all(color: RD.green.withValues(alpha: 0.4)),
      ),
      alignment: Alignment.center,
      child: Text(
        'MARION COUNTY EXPLORE',
        style: RD.badge.copyWith(color: RD.greenBright, letterSpacing: 1.4),
      ),
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
            label: const Text(
              'Back to radio',
              style: TextStyle(color: RD.green),
            ),
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
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static String _date(DateTime d) =>
      '${_days[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';
}
