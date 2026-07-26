import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/destinations/providers/destinations_provider.dart';
import 'package:explorer_os_mobile/features/maps/models/nearby_item.dart';
import 'package:explorer_os_mobile/features/maps/providers/map_layers_provider.dart';
import 'package:explorer_os_mobile/features/maps/providers/map_places_provider.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';
import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
import 'package:explorer_os_mobile/features/story_studio/data/story_library_repository.dart';
import 'package:explorer_os_mobile/features/story_studio/services/gps_story_selector.dart';
import 'package:explorer_os_mobile/features/radio/providers/radio_session_provider.dart';
import 'package:explorer_os_mobile/features/radio/providers/stations_provider.dart';
import 'package:explorer_os_mobile/features/sightings/models/explorer_sighting.dart';
import 'package:explorer_os_mobile/features/sightings/providers/sighting_providers.dart';
import 'package:explorer_os_mobile/shared/models/destination.dart';
import 'package:explorer_os_mobile/shared/models/radio_station.dart';
import 'package:explorer_os_mobile/shared/models/stop.dart';

/// Palette for the immersive (dark) Map screen.
class _MapPalette {
  static const Color bg = Color(0xFF0E1512);
  static const Color header = Color(0xFF141C18);
  static const Color control = Color(0xFF1B2420);
  static const Color gold = Color(0xFFF2B33D);
  static const Color green = Color(0xFF2E9E6B);
  static const Color textPrimary = Color(0xFFF3F6F2);
  static const Color textSecondary = Color(0xFF9CA8A1);
}

/// The Map tab — a full-bleed Google Map (satellite/hybrid) that plots
/// destinations (Base44 `latitude`/`longitude`) as circular icon markers, with
/// floating controls and a "nearest place" card that reflects the map center.
class MapsScreen extends ConsumerStatefulWidget {
  const MapsScreen({super.key});

  /// Fallback camera target (central Florida) until a destination is available.
  static const _fallbackCenter = LatLng(29.1872, -81.7137);

  @override
  ConsumerState<MapsScreen> createState() => _MapsScreenState();
}

class _MapsScreenState extends ConsumerState<MapsScreen> {
  GoogleMapController? _controller;
  BitmapDescriptor? _pinIcon;
  BitmapDescriptor? _sightingIcon;
  BitmapDescriptor? _locationIcon;
  BitmapDescriptor? _poiIcon;
  BitmapDescriptor? _campIcon;
  final Map<String, BitmapDescriptor> _categoryIcons = {};
  bool _centerInitialized = false;
  bool _fittedPlaces = false; // auto-fit bounds to places once

  // Explorer Mode + simulated drive + GPS story triggers.
  bool _explorerMode = true;
  Timer? _drive;
  int _driveIndex = 0;
  List<LatLng> _route = const [];
  final Set<String> _notified = {}; // notified once per approach
  final Set<String> _inZone = {}; // items whose trigger zone we're inside
  final _storySelector = GpsStorySelector();
  final Set<String> _storiesPlayed = {}; // GPS stories played this visit
  ({String text, IconData icon, Color color})? _banner;
  Timer? _bannerTimer;

  static const double _notifyMeters = 180;
  static const double _triggerMeters = 120;
  static const _triggerCategories = {'springs', 'historic_sites', 'waterfalls'};

  @override
  void dispose() {
    _drive?.cancel();
    _bannerTimer?.cancel();
    super.dispose();
  }

  double _metersBetween(LatLng a, LatLng b) {
    const earth = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(a.latitude * math.pi / 180) *
            math.cos(b.latitude * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earth * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  /// Start/stop a simulated drive (stands in for live device GPS on web). The
  /// user dot follows the route; proximity + story triggers fire en route.
  void _toggleDrive() {
    if (_drive != null) {
      _drive!.cancel();
      setState(() => _drive = null);
      return;
    }
    final start = ref.read(mapCenterProvider) ?? MapsScreen._fallbackCenter;
    // Route heading toward the farthest seeded points (e.g. Juniper Spring).
    _route = [
      for (var i = 0; i <= 12; i++)
        LatLng(start.latitude + 0.02 * (i / 12),
            start.longitude + 0.001 * (i / 12)),
    ];
    _driveIndex = 0;
    _notified.clear();
    _inZone.clear();
    setState(() {});
    _drive = Timer.periodic(const Duration(milliseconds: 1400), (t) {
      if (_driveIndex >= _route.length) {
        t.cancel();
        if (mounted) setState(() => _drive = null);
        return;
      }
      final loc = _route[_driveIndex++];
      ref.read(mapCenterProvider.notifier).set(loc);
      _controller?.animateCamera(CameraUpdate.newLatLngZoom(loc, 14));
      _scanProximity(loc);
    });
  }

  /// Explorer Mode: notify on approach; fire GPS story triggers once per entry.
  void _scanProximity(LatLng loc) {
    // Story Studio: play a published, GPS-zoned story when the visitor enters
    // its radius (once per visit, avoiding repeats).
    final stories = ref.read(playableStoriesProvider).value ?? const [];
    if (stories.isNotEmpty) {
      final story = _storySelector.select(stories, loc.latitude, loc.longitude,
          alreadyPlayed: _storiesPlayed);
      if (story != null) {
        _storiesPlayed.add(story.id);
        ref.read(radioEngineControllerProvider.notifier).requestInterruption(
              AudioSegment(
                id: 'story:${story.id}:${DateTime.now().millisecondsSinceEpoch}',
                title: story.title,
                type: AudioSegmentType.gpsNarration,
                priority: PlaybackPriority.gpsNarration,
                audioUrl: story.audioUrl,
                interruptible: true,
                resumeAfter: true,
              ),
            );
        _showBanner('Now playing: ${story.title}', Icons.menu_book_rounded,
            _MapPalette.gold);
      }
    }

    final all = ref.read(mapLocationsProvider).value ?? const [];
    for (final item in all) {
      final m = _metersBetween(loc, LatLng(item.latitude, item.longitude));
      final style = nearbyStyle(item.category);
      final isTrigger = _triggerCategories.contains(item.category);

      // GPS story trigger (enter zone once): pause Radio → narration → resume.
      if (isTrigger) {
        if (m <= _triggerMeters && !_inZone.contains(item.id)) {
          _inZone.add(item.id);
          _fireStoryTrigger(item.name, style);
        } else if (m > _triggerMeters * 1.6) {
          _inZone.remove(item.id); // left the zone → can re-trigger later
        }
      }

      // Explorer Mode proximity notification (once per approach).
      if (_explorerMode &&
          m <= _notifyMeters &&
          !_notified.contains(item.id) &&
          !isTrigger) {
        _notified.add(item.id);
        _showBanner('${item.name} nearby', style.icon, style.color);
      }
    }
  }

  void _fireStoryTrigger(String name, NearbyStyle style) {
    // Pause Explorer Radio, "play" the narration, resume afterwards.
    final radio = ref.read(radioEngineControllerProvider.notifier);
    radio.pause();
    _showBanner('Now playing: $name narration', Icons.play_circle_rounded,
        _MapPalette.gold);
    Timer(const Duration(seconds: 5), () {
      if (mounted) radio.resume();
    });
  }

  void _showBanner(String text, IconData icon, Color color) {
    _bannerTimer?.cancel();
    setState(() => _banner = (text: text, icon: icon, color: color));
    _bannerTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _banner = null);
    });
  }

  static const _nearbyCategoryTokens = [
    'mammals', 'birds', 'reptiles', 'amphibians', 'fish', 'plants', 'trees',
    'wildflowers', 'mushrooms', 'springs', 'waterfalls', 'scenic_overlooks',
    'historic_sites', 'trails', 'campgrounds', 'visitor_centers',
    'ranger_stations', 'fishing_areas', 'boat_ramps',
  ];

  @override
  void initState() {
    super.initState();
    _buildIcons();
  }

  /// Icon for a place category. Campgrounds get the cabin icon; unknown/POI
  /// categories get a distinct orange place pin (never a blank default).
  BitmapDescriptor _iconFor(String category) {
    if (category == 'campgrounds') {
      return _campIcon ?? _categoryIcons['campgrounds'] ?? _fallbackPin;
    }
    return _categoryIcons[category] ?? _poiIcon ?? _fallbackPin;
  }

  static final BitmapDescriptor _fallbackPin =
      BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);

  /// Renders circular icon markers to bitmaps (green = parks, blue = locations,
  /// amber = sightings) so pins look like the design.
  Future<void> _buildIcons() async {
    try {
      final pin =
          await _circleIconMarker(Icons.forest_rounded, _MapPalette.green);
      final location = await _circleIconMarker(
          Icons.place_rounded, const Color(0xFF3F8FD0));
      final sighting = await _circleIconMarker(
          Icons.visibility_rounded, _MapPalette.gold);
      // Distinct icons for the two always-on place types (requirement #9).
      final poi = await _circleIconMarker(
          Icons.place_rounded, const Color(0xFFEE7B2E));
      final camp = await _circleIconMarker(
          Icons.cabin_rounded, const Color(0xFF7C8B3A));
      final cats = <String, BitmapDescriptor>{};
      for (final token in _nearbyCategoryTokens) {
        final style = nearbyStyle(token);
        cats[token] = await _circleIconMarker(style.icon, style.color, size: 96);
      }
      if (mounted) {
        setState(() {
          _pinIcon = pin;
          _locationIcon = location;
          _sightingIcon = sighting;
          _poiIcon = poi;
          _campIcon = camp;
          _categoryIcons.addAll(cats);
        });
      }
    } catch (_) {
      // Fall back to the default marker if bitmap rendering is unavailable.
    }
  }

  static Future<BitmapDescriptor> _circleIconMarker(
    IconData icon,
    Color color, {
    double size = 120,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final radius = size / 2;
    canvas.drawCircle(Offset(radius, radius), radius, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(radius, radius), radius - 7, Paint()..color = color);
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size * 0.5,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
        ),
      )
      ..layout();
    tp.paint(canvas, Offset(radius - tp.width / 2, radius - tp.height / 2));
    final image =
        await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  // --- Marker detail sheets (tap a marker to explore) ----------------------

  void _openParkSheet(Destination d) => _showDetail(
        title: d.name,
        subtitle: d.location ?? d.category ?? 'Park',
        imageUrl: d.imageUrl,
        icon: Icons.forest_rounded,
        color: _MapPalette.green,
        actions: [
          FilledButton.icon(
            onPressed: () {
              ref
                  .read(selectedStationProvider.notifier)
                  .select(RadioStation.fromDestination(d));
              ref.invalidate(radioSessionProvider);
              Navigator.of(context).maybePop();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content:
                    Text('Tuned to ${d.name} Radio — open the Radio tab'),
              ));
            },
            icon: const Icon(Icons.podcasts_rounded, size: 18),
            label: const Text('Tune Radio'),
          ),
        ],
      );

  void _openStopSheet(Stop s) => _showDetail(
        title: s.name,
        subtitle: s.stopType ?? 'Location',
        imageUrl: s.imageUrl,
        icon: Icons.place_rounded,
        color: const Color(0xFF3F8FD0),
      );

  void _openSightingSheet(ExplorerSighting s) => _showDetail(
        title: s.species ?? s.category.label,
        subtitle: 'Sighting · ${s.category.label}'
            '${s.notes != null ? ' · ${s.notes}' : ''}',
        icon: s.category.icon,
        color: _MapPalette.gold,
      );

  void _showDetail({
    required String title,
    String? subtitle,
    String? imageUrl,
    required IconData icon,
    required Color color,
    List<Widget> actions = const [],
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: _MapPalette.control,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: AppRadius.lgAll,
              child: SizedBox(
                height: 150,
                child: (imageUrl != null && imageUrl.isNotEmpty)
                    ? Image.network(imageUrl, fit: BoxFit.cover)
                    : Container(
                        color: color.withValues(alpha: 0.2),
                        child: Icon(icon, color: color, size: 48),
                      ),
              ),
            ),
            const Gap.v(AppSpacing.md),
            Row(
              children: [
                Icon(icon, color: color, size: 22),
                const Gap.h(AppSpacing.sm),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          color: _MapPalette.textPrimary,
                          fontSize: 19,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const Gap.v(AppSpacing.xs),
              Text(subtitle,
                  style: const TextStyle(
                      color: _MapPalette.textSecondary, fontSize: 13)),
            ],
            if (actions.isNotEmpty) ...[
              const Gap.v(AppSpacing.lg),
              ...actions,
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final destinations = ref.watch(destinationsProvider).value ?? const [];
    final mappable =
        destinations.where((d) => d.hasCoordinates).toList(growable: false);
    final sightings = ref.watch(recentSightingsProvider).value ?? const [];
    final stops = ref.watch(allStopsProvider).value ?? const [];
    final layers = ref.watch(mapLayersProvider);
    ref.watch(playableStoriesProvider); // preload GPS-triggered stories

    // Establish the user's location (device GPS on hardware; a simulated
    // center — the first destination — on web) once, so nearby search runs.
    if (!_centerInitialized) {
      final seed = mappable.isNotEmpty
          ? LatLng(mappable.first.latitude!, mappable.first.longitude!)
          : MapsScreen._fallbackCenter;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(mapCenterProvider) == null) {
          ref.read(mapCenterProvider.notifier).set(seed);
        }
      });
      _centerInitialized = true;
    }

    final userLocation = ref.watch(mapCenterProvider);
    final hits = ref.watch(nearbyItemsProvider);
    final radius = ref.watch(searchRadiusProvider);
    // Always-on POI + campground markers (not gated by the search radius).
    final places = ref.watch(mapPlacesProvider);

    final markers = <Marker>{
      if (layers.contains(MapLayer.parks))
        for (final d in mappable)
          Marker(
            markerId: MarkerId('park_${d.id}'),
            position: LatLng(d.latitude!, d.longitude!),
            icon: _pinIcon ?? BitmapDescriptor.defaultMarker,
            onTap: () => _openParkSheet(d),
          ),
      if (layers.contains(MapLayer.locations))
        for (final s in stops.where((s) => s.latitude != null && s.longitude != null))
          Marker(
            markerId: MarkerId('stop_${s.id}'),
            position: LatLng(s.latitude!, s.longitude!),
            icon: _locationIcon ??
                BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueAzure),
            onTap: () => _openStopSheet(s),
          ),
      if (layers.contains(MapLayer.sightings))
        for (final s in sightings.where((s) => s.hasCoordinates))
          Marker(
            markerId: MarkerId('sighting_${s.id}'),
            position: LatLng(s.latitude!, s.longitude!),
            icon: _sightingIcon ??
                BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueOrange),
            onTap: () => _openSightingSheet(s),
          ),
      // Points of Interest (map_locations) + Campgrounds — every valid record,
      // always visible (not radius-filtered), each with its own icon.
      if (layers.contains(MapLayer.locations))
        for (final p in places)
          Marker(
            markerId: MarkerId('place_${p.id}'),
            position: LatLng(p.latitude, p.longitude),
            icon: _iconFor(p.category),
            onTap: () => _openPlaceSheet(p),
          ),
      // User location (blue dot).
      if (userLocation != null)
        Marker(
          markerId: const MarkerId('_user'),
          position: userLocation,
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'You are here'),
        ),
    };

    debugPrint('[Map] markers built: ${markers.length} '
        '(places/POI+campgrounds=${places.length}, parks=${mappable.length}, '
        'stops=${stops.length}, sightings=${sightings.length})');

    // Auto-fit the camera once so every place/park marker is in view, even if
    // records sit outside the initial viewport (requirement #7/#8).
    if (!_fittedPlaces && _controller != null) {
      final pts = <LatLng>[
        for (final p in places) LatLng(p.latitude, p.longitude),
        for (final d in mappable) LatLng(d.latitude!, d.longitude!),
      ];
      if (pts.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFitBounds(pts));
      }
    }

    // Park boundaries (approximate circles until real polygons/geojson exist).
    final circles = <Circle>{
      if (layers.contains(MapLayer.boundaries))
        for (final d in mappable)
          Circle(
            circleId: CircleId('boundary_${d.id}'),
            center: LatLng(d.latitude!, d.longitude!),
            radius: 12000, // ~12 km placeholder
            strokeColor: _MapPalette.green,
            strokeWidth: 2,
            fillColor: _MapPalette.green.withValues(alpha: 0.08),
          ),
      // GPS accuracy ring around the user.
      if (userLocation != null)
        Circle(
          circleId: const CircleId('_accuracy'),
          center: userLocation,
          radius: 60,
          strokeColor: const Color(0xFF3F8FD0),
          strokeWidth: 1,
          fillColor: const Color(0x223F8FD0),
        ),
    };

    final initialTarget = mappable.isNotEmpty
        ? LatLng(mappable.first.latitude!, mappable.first.longitude!)
        : MapsScreen._fallbackCenter;

    return Scaffold(
      backgroundColor: _MapPalette.bg,
      body: Column(
        children: [
          _header(),
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition:
                      CameraPosition(target: initialTarget, zoom: 9),
                  markers: markers,
                  circles: circles,
                  mapType: MapType.hybrid,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  onMapCreated: (c) {
                    _controller = c;
                    // Trigger a rebuild so the auto-fit block runs now that the
                    // controller exists.
                    if (mounted) setState(() {});
                  },
                ),
                _controls(initialTarget, userLocation),
                _layerChips(layers),
                _radiusSelector(radius),
                _explorerModeToggle(),
                _aroundMeButton(hits.length),
                if (_banner != null) _bannerOverlay(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Search-radius pill (top-right, below the controls) with a menu of radii.
  Widget _radiusSelector(SearchRadius radius) {
    return Positioned(
      top: 56,
      left: AppSpacing.lg,
      child: PopupMenuButton<SearchRadius>(
        tooltip: 'Search radius',
        onSelected: (r) {
          ref.read(searchRadiusProvider.notifier).set(r);
          WidgetsBinding.instance.addPostFrameCallback((_) => _fitToNearby());
        },
        itemBuilder: (context) => [
          for (final r in SearchRadius.values)
            PopupMenuItem(value: r, child: Text(r.label)),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: _MapPalette.control,
            borderRadius: AppRadius.pillAll,
            boxShadow: const [
              BoxShadow(color: Color(0x66000000), blurRadius: 8)
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.radar_rounded,
                  color: _MapPalette.gold, size: 16),
              const SizedBox(width: 6),
              Text(radius.label,
                  style: const TextStyle(
                      color: _MapPalette.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const Icon(Icons.arrow_drop_down_rounded,
                  color: _MapPalette.textSecondary, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  /// Floating "Around Me" button with a live count of nearby items.
  Widget _aroundMeButton(int count) {
    return Positioned(
      left: AppSpacing.lg,
      bottom: 110,
      child: FloatingActionButton.extended(
        heroTag: 'aroundMe',
        backgroundColor: _MapPalette.gold,
        foregroundColor: Colors.black,
        onPressed: _openAroundMe,
        icon: const Icon(Icons.explore_rounded),
        label: Text('Around Me ($count)'),
      ),
    );
  }

  void _fitToNearby() {
    final center = ref.read(mapCenterProvider);
    final hits = ref.read(nearbyItemsProvider);
    if (center == null || _controller == null) return;
    if (hits.isEmpty) {
      _controller!.animateCamera(CameraUpdate.newLatLngZoom(center, 13));
      return;
    }
    var minLat = center.latitude, maxLat = center.latitude;
    var minLng = center.longitude, maxLng = center.longitude;
    for (final h in hits) {
      minLat = math.min(minLat, h.item.latitude);
      maxLat = math.max(maxLat, h.item.latitude);
      minLng = math.min(minLng, h.item.longitude);
      maxLng = math.max(maxLng, h.item.longitude);
    }
    _controller!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      ),
      64,
    ));
  }

  /// The draggable "Around Me" panel: categories (grouped) with counts, each
  /// expanding into nearby items sorted by distance.
  void _openAroundMe() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _MapPalette.control,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        builder: (context, scrollController) {
          final hits = ref.read(nearbyItemsProvider);
          final groups = <String, List<NearbyHit>>{};
          for (final h in hits) {
            groups.putIfAbsent(nearbyStyle(h.item.category).group, () => []).add(h);
          }
          final groupNames = groups.keys.toList()
            ..sort((a, b) => groups[b]!.length.compareTo(groups[a]!.length));
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xl),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: _MapPalette.textSecondary,
                    borderRadius: AppRadius.pillAll,
                  ),
                ),
              ),
              Text('Around Me',
                  style: const TextStyle(
                      color: _MapPalette.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
              Text('${hits.length} nearby · ${ref.read(searchRadiusProvider).label}',
                  style: const TextStyle(color: _MapPalette.textSecondary)),
              const Gap.v(AppSpacing.md),
              if (hits.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: Text('Nothing within range — widen the radius.',
                      style: TextStyle(color: _MapPalette.textSecondary)),
                ),
              for (final name in groupNames)
                _AroundMeGroup(
                  title: name,
                  hits: groups[name]!,
                  onSelect: (hit) {
                    Navigator.of(context).maybePop();
                    _controller?.animateCamera(CameraUpdate.newLatLngZoom(
                        LatLng(hit.item.latitude, hit.item.longitude), 15));
                    _openNearbySheet(hit);
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  /// Detail sheet for an always-on place marker (POI / campground).
  void _openPlaceSheet(NearbyItem item) {
    final style = nearbyStyle(item.category);
    _showDetail(
      title: item.name,
      subtitle: item.description ?? style.group,
      imageUrl: item.imageUrl,
      icon: style.icon,
      color: style.color,
      actions: [_nearbyActionRow()],
    );
  }

  /// Fit the camera to include all provided points (extends bounds so markers
  /// outside the current viewport become visible). Runs once.
  void _maybeFitBounds(List<LatLng> pts) {
    if (_fittedPlaces || _controller == null || pts.isEmpty) return;
    _fittedPlaces = true;
    if (pts.length == 1) {
      _controller!.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 13));
      return;
    }
    var minLat = pts.first.latitude, maxLat = pts.first.latitude;
    var minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    // Degenerate (all points nearly identical) → just zoom to it.
    if ((maxLat - minLat).abs() < 0.0008 && (maxLng - minLng).abs() < 0.0008) {
      _controller!
          .animateCamera(CameraUpdate.newLatLngZoom(pts.first, 13));
      return;
    }
    _controller!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      ),
      64,
    ));
  }

  void _openNearbySheet(NearbyHit hit) {
    final style = nearbyStyle(hit.item.category);
    _showDetail(
      title: hit.item.name,
      subtitle: '${formatDistance(hit.meters)}'
          '${hit.item.description != null ? ' · ${hit.item.description}' : ''}',
      imageUrl: hit.item.imageUrl,
      icon: style.icon,
      color: style.color,
      actions: [_nearbyActionRow()],
    );
  }

  Widget _nearbyActionRow() {
    const items = <(String, IconData)>[
      ('Navigate', Icons.navigation_rounded),
      ('Play Audio', Icons.volume_up_rounded),
      ('Gallery', Icons.photo_library_rounded),
      ('Favorite', Icons.favorite_border_rounded),
      ('Journal', Icons.book_rounded),
      ('Ask AI Ranger', Icons.smart_toy_rounded),
    ];
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final (label, icon) in items)
          OutlinedButton.icon(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$label — coming soon')),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 40),
              foregroundColor: _MapPalette.textPrimary,
              side: const BorderSide(color: Color(0xFF2E3A34)),
            ),
            icon: Icon(icon, size: 16),
            label: Text(label),
          ),
      ],
    );
  }

  /// Quick horizontal layer toggles overlaid at the top of the map.
  Widget _layerChips(Set<MapLayer> active) {
    return Positioned(
      top: AppSpacing.md,
      left: AppSpacing.md,
      right: 72, // leave room for the control column
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final layer in MapLayer.values)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: _LayerChip(
                  layer: layer,
                  active: active.contains(layer),
                  onTap: () =>
                      ref.read(mapLayersProvider.notifier).toggle(layer),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      color: _MapPalette.header,
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.menu_rounded,
                  color: _MapPalette.textPrimary),
            ),
            const Expanded(
              child: Text(
                'Map',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _MapPalette.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.tune_rounded,
                  color: _MapPalette.textPrimary),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  Widget _controls(LatLng fallbackTarget, LatLng? userLocation) {
    return Positioned(
      top: AppSpacing.lg,
      right: AppSpacing.lg,
      child: Column(
        children: [
          _controlButton(
            Icons.my_location_rounded,
            () => _controller?.animateCamera(CameraUpdate.newLatLngZoom(
                userLocation ?? fallbackTarget, 14)),
          ),
          const Gap.v(AppSpacing.md),
          _controlButton(
              Icons.add_rounded, () => _controller?.animateCamera(CameraUpdate.zoomIn())),
          const Gap.v(AppSpacing.sm),
          _controlButton(Icons.remove_rounded,
              () => _controller?.animateCamera(CameraUpdate.zoomOut())),
          const Gap.v(AppSpacing.md),
          _controlButton(
            _drive != null
                ? Icons.stop_rounded
                : Icons.directions_car_rounded,
            _toggleDrive,
            tint: _drive != null ? _MapPalette.gold : _MapPalette.textPrimary,
          ),
        ],
      ),
    );
  }

  Widget _controlButton(IconData icon, VoidCallback onTap,
      {Color tint = _MapPalette.textPrimary}) {
    return Material(
      color: _MapPalette.control,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: tint, size: 22),
        ),
      ),
    );
  }

  /// Explorer Mode pill (top-right, below the radius selector).
  Widget _explorerModeToggle() {
    return Positioned(
      top: 102,
      left: AppSpacing.lg,
      child: GestureDetector(
        onTap: () => setState(() => _explorerMode = !_explorerMode),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: _explorerMode ? _MapPalette.gold : _MapPalette.control,
            borderRadius: AppRadius.pillAll,
            boxShadow: const [
              BoxShadow(color: Color(0x66000000), blurRadius: 8)
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 15,
                  color: _explorerMode ? Colors.black : _MapPalette.textSecondary),
              const SizedBox(width: 6),
              Text('Explorer Mode',
                  style: TextStyle(
                      color:
                          _explorerMode ? Colors.black : _MapPalette.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  /// A subtle, auto-dismissing notification banner (never blocks navigation).
  Widget _bannerOverlay() {
    final b = _banner!;
    return Positioned(
      top: 60,
      left: AppSpacing.lg,
      right: AppSpacing.lg,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: _MapPalette.control.withValues(alpha: 0.96),
              borderRadius: AppRadius.pillAll,
              border: Border.all(color: b.color.withValues(alpha: 0.7)),
              boxShadow: const [
                BoxShadow(color: Color(0x88000000), blurRadius: 14)
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(b.icon, color: b.color, size: 18),
                const Gap.h(AppSpacing.sm),
                Flexible(
                  child: Text(b.text,
                      style: const TextStyle(
                          color: _MapPalette.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A single map-layer toggle pill.
class _LayerChip extends StatelessWidget {
  const _LayerChip({
    required this.layer,
    required this.active,
    required this.onTap,
  });

  final MapLayer layer;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? _MapPalette.green : _MapPalette.control.withValues(alpha: 0.92),
      borderRadius: AppRadius.pillAll,
      elevation: 3,
      child: InkWell(
        borderRadius: AppRadius.pillAll,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(layer.icon,
                  size: 15,
                  color: active ? Colors.white : _MapPalette.textSecondary),
              const SizedBox(width: 5),
              Text(layer.label,
                  style: TextStyle(
                      color: active ? Colors.white : _MapPalette.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A collapsible category group in the Around Me panel.
class _AroundMeGroup extends StatelessWidget {
  const _AroundMeGroup({
    required this.title,
    required this.hits,
    required this.onSelect,
  });

  final String title;
  final List<NearbyHit> hits;
  final void Function(NearbyHit) onSelect;

  @override
  Widget build(BuildContext context) {
    final style = nearbyStyle(hits.first.item.category);
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        listTileTheme: const ListTileThemeData(dense: true),
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: AppSpacing.sm),
        iconColor: _MapPalette.textSecondary,
        collapsedIconColor: _MapPalette.textSecondary,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: style.color.withValues(alpha: 0.2),
          child: Icon(style.icon, color: style.color, size: 18),
        ),
        title: Text('$title (${hits.length})',
            style: const TextStyle(
                color: _MapPalette.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 15)),
        children: [
          for (final h in hits)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              title: Text(h.item.name,
                  style: const TextStyle(
                      color: _MapPalette.textPrimary, fontSize: 14)),
              trailing: Text(formatDistance(h.meters),
                  style: const TextStyle(
                      color: _MapPalette.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              onTap: () => onSelect(h),
            ),
        ],
      ),
    );
  }
}
