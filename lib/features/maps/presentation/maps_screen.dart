import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/destinations/providers/destinations_provider.dart';
import 'package:explorer_os_mobile/features/location_intelligence/data/location_content_repository.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/locations/presentation/destination_detail_card.dart';
import 'package:explorer_os_mobile/features/maps/marker_style.dart';
import 'package:explorer_os_mobile/features/maps/models/nearby_item.dart';
import 'package:explorer_os_mobile/features/maps/providers/map_layers_provider.dart';
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

/// Active map category filter — the set of legend keys currently shown.
/// Defaults to every category.
class MapCategoryFilter extends Notifier<Set<String>> {
  @override
  Set<String> build() => {for (final s in markerLegend) s.key};
  void toggle(String key) {
    final next = {...state};
    if (!next.remove(key)) next.add(key);
    state = next;
  }

  void showAll() => state = {for (final s in markerLegend) s.key};
}

final mapCategoryFilterProvider =
    NotifierProvider<MapCategoryFilter, Set<String>>(MapCategoryFilter.new);

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
  // Category pin bitmaps, keyed by '<styleKey>:<selected>'. Built once.
  final Map<String, BitmapDescriptor> _pins = {};
  // The currently highlighted marker + the data behind its bottom info card.
  _MapSelection? _selection;
  static const _placesCluster = ClusterManagerId('places');
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

  @override
  void initState() {
    super.initState();
    _buildIcons();
  }

  static final BitmapDescriptor _fallbackPin =
      BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);

  /// The cached pin bitmap for a category [style], normal or [selected].
  BitmapDescriptor _pin(MarkerCategoryStyle style, {bool selected = false}) =>
      _pins['${style.key}:$selected'] ?? _fallbackPin;

  /// Renders a crisp, category-colored teardrop pin for every legend category
  /// (plus a park pin), in normal and selected variants, once.
  Future<void> _buildIcons() async {
    try {
      final styles = [...markerLegend, parkMarkerStyle];
      final built = <String, BitmapDescriptor>{};
      for (final s in styles) {
        built['${s.key}:false'] = await _pinBitmap(s, selected: false);
        built['${s.key}:true'] = await _pinBitmap(s, selected: true);
      }
      if (mounted) {
        setState(() => _pins.addAll(built));
      }
    } catch (_) {
      // Fall back to default markers if bitmap rendering is unavailable.
    }
  }

  /// Draws a scalable teardrop marker filled with the category color, a white
  /// glyph, and (when [selected]) a larger body, highlight halo, and drop
  /// shadow. Rendered at 3x and tagged with imagePixelRatio so it stays crisp.
  static Future<BitmapDescriptor> _pinBitmap(
    MarkerCategoryStyle style, {
    bool selected = false,
  }) async {
    const dpr = 3.0;
    final w = selected ? 58.0 : 44.0;
    final h = selected ? 76.0 : 58.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(dpr);

    final headR = w * 0.40;
    final cx = w / 2;
    final cy = headR + (selected ? 6.0 : 3.0);
    final tipY = h - 1;

    // Drop shadow (stronger when selected) under the tip.
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: selected ? 0.34 : 0.22)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, selected ? 5 : 3);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, tipY - 2), width: headR * 1.1, height: headR * 0.5),
      shadowPaint,
    );

    // Selected: soft colored halo around the head.
    if (selected) {
      canvas.drawCircle(Offset(cx, cy), headR * 1.42,
          Paint()..color = style.color.withValues(alpha: 0.22));
    }

    final fill = Paint()..color = style.color;
    // Tail (triangle from head to the tip), then the head circle over it.
    final tail = Path()
      ..moveTo(cx - headR * 0.62, cy + headR * 0.45)
      ..lineTo(cx, tipY)
      ..lineTo(cx + headR * 0.62, cy + headR * 0.45)
      ..close();
    canvas.drawPath(tail, fill);
    canvas.drawCircle(Offset(cx, cy), headR, fill);
    // White ring around the head.
    canvas.drawCircle(
      Offset(cx, cy),
      headR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 3.4 : 2.6
        ..color = Colors.white,
    );
    // Inner white disc so the glyph reads on any color.
    canvas.drawCircle(
        Offset(cx, cy), headR * 0.60, Paint()..color = Colors.white);

    final glyph = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(style.icon.codePoint),
        style: TextStyle(
          fontSize: headR * 0.92,
          fontFamily: style.icon.fontFamily,
          package: style.icon.fontPackage,
          color: style.color,
        ),
      )
      ..layout();
    glyph.paint(canvas, Offset(cx - glyph.width / 2, cy - glyph.height / 2));

    final image = await recorder
        .endRecording()
        .toImage((w * dpr).toInt(), (h * dpr).toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(),
        imagePixelRatio: dpr);
  }

  void _select(_MapSelection selection) {
    setState(() => _selection = selection);
  }

  /// Zoom into a cluster's bounds so it expands into individual markers.
  void _onClusterTap(Cluster cluster) {
    final c = _controller;
    if (c == null) return;
    try {
      c.animateCamera(CameraUpdate.newLatLngBounds(cluster.bounds, 72));
    } catch (_) {
      c.animateCamera(CameraUpdate.newLatLngZoom(cluster.position, 14));
    }
  }

  /// Builds a category-colored pin marker that highlights (larger + shadow)
  /// while it's the current selection and opens the bottom info card on tap.
  Marker _placeMarker({
    required String id,
    required LatLng position,
    required MarkerCategoryStyle style,
    required _MapSelection selection,
    bool clustered = false,
    VoidCallback? onTap,
  }) {
    final selected = _selection?.markerId == id;
    return Marker(
      markerId: MarkerId(id),
      position: position,
      icon: _pin(style, selected: selected),
      anchor: const Offset(0.5, 1),
      zIndexInt: selected ? 3 : 1,
      clusterManagerId: clustered ? _placesCluster : null,
      onTap: onTap ?? () => _select(selection),
    );
  }

  /// Opens the ONE universal Destination Detail card for a tapped place marker
  /// (master locations). Falls back to the legacy selection card otherwise.
  void _openPlaceDetail(NearbyItem p, _MapSelection selection) {
    const prefix = 'locations:';
    if (p.id.startsWith(prefix)) {
      final locId = p.id.substring(prefix.length);
      final all = ref.read(masterLocationsProvider).value ?? const [];
      for (final l in all) {
        if (l.id == locId) {
          final center = ref.read(mapCenterProvider);
          final dist = center == null
              ? null
              : GeoMath.distanceMeters(
                  center.latitude, center.longitude, p.latitude, p.longitude);
          showDestinationDetail(context, l, distanceMeters: dist);
          return;
        }
      }
    }
    _select(selection);
  }

  // --- Bottom info card actions -------------------------------------------
  void _listen(_MapSelection sel) {
    final messenger = ScaffoldMessenger.of(context);
    if (sel.park != null) {
      ref
          .read(selectedStationProvider.notifier)
          .select(RadioStation.fromDestination(sel.park!));
      ref.invalidate(radioSessionProvider);
      messenger.showSnackBar(SnackBar(
          content: Text('Tuned to ${sel.park!.name} Radio — open the Radio tab')));
      return;
    }
    if (sel.audioUrl != null && sel.audioUrl!.isNotEmpty) {
      ref.read(radioEngineControllerProvider.notifier).requestInterruption(
            AudioSegment(
              id: 'poi:${sel.markerId}:${DateTime.now().millisecondsSinceEpoch}',
              title: sel.name,
              type: AudioSegmentType.gpsNarration,
              priority: PlaybackPriority.gpsNarration,
              audioUrl: sel.audioUrl,
              interruptible: true,
              resumeAfter: true,
            ),
          );
      messenger.showSnackBar(
          SnackBar(content: Text('Playing ${sel.name} on Explorer Radio')));
      return;
    }
    messenger.showSnackBar(
        SnackBar(content: Text('No narration for ${sel.name} yet')));
  }

  void _navigateTo(_MapSelection sel) {
    _controller?.animateCamera(CameraUpdate.newLatLngZoom(sel.position, 15));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Navigating to ${sel.name}')));
  }

  void _moreInfo(_MapSelection sel, String? distance) {
    _showDetail(
      title: sel.name,
      subtitle:
          '${sel.style.label}${distance != null ? ' · $distance' : ''}',
      imageUrl: sel.imageUrl,
      icon: sel.style.icon,
      color: sel.style.color,
      actions: [_nearbyActionRow()],
    );
  }

  // --- Marker detail sheets (tap a marker to explore) ----------------------

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
    // Location Intelligence: plot only places within ~20 miles of the user
    // (dynamic — recomputes as they drive; out-of-range places fall away).
    // Falls back to all places until the first GPS fix.
    final visible = ref.watch(visibleMapPlacesProvider);
    final catFilter = ref.watch(mapCategoryFilterProvider);
    final places = [
      for (final v in visible)
        if (catFilter.contains(markerStyleForItem(
                v.item.category, v.item.name, v.item.subcategory)
            .key))
          v.item,
    ];
    final highlightedIds = {
      for (final v in visible)
        if (v.highlight) v.item.id,
    };

    final markers = <Marker>{
      if (layers.contains(MapLayer.parks))
        for (final d in mappable)
          _placeMarker(
            id: 'park_${d.id}',
            position: LatLng(d.latitude!, d.longitude!),
            style: parkMarkerStyle,
            selection: _MapSelection(
              markerId: 'park_${d.id}',
              name: d.name,
              style: parkMarkerStyle,
              position: LatLng(d.latitude!, d.longitude!),
              imageUrl: d.imageUrl,
              park: d,
            ),
          ),
      if (layers.contains(MapLayer.locations))
        for (final s in stops.where((s) => s.latitude != null && s.longitude != null))
          Marker(
            markerId: MarkerId('stop_${s.id}'),
            position: LatLng(s.latitude!, s.longitude!),
            icon: _pin(markerStyleFor('other')),
            onTap: () => _openStopSheet(s),
          ),
      if (layers.contains(MapLayer.sightings))
        for (final s in sightings.where((s) => s.hasCoordinates))
          Marker(
            markerId: MarkerId('sighting_${s.id}'),
            position: LatLng(s.latitude!, s.longitude!),
            icon: _pin(markerStyleFor('wildlife_viewing')),
            onTap: () => _openSightingSheet(s),
          ),
      // Points of Interest (map_locations) + Campgrounds — category-colored,
      // clustered when zoomed out, each with a selectable info card.
      if (layers.contains(MapLayer.locations))
        for (final p in places)
          () {
            final selection = _MapSelection(
              markerId: 'place_${p.id}',
              name: p.name,
              style: markerStyleForItem(p.category, p.name, p.subcategory),
              position: LatLng(p.latitude, p.longitude),
              imageUrl: p.imageUrl,
              audioUrl: p.audioUrl,
            );
            return _placeMarker(
              id: 'place_${p.id}',
              position: LatLng(p.latitude, p.longitude),
              style: markerStyleForItem(p.category, p.name, p.subcategory),
              clustered: true,
              selection: selection,
              // Tapping a place opens the ONE universal Destination Detail card.
              onTap: () => _openPlaceDetail(p, selection),
            );
          }(),
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
      // Highlight places within 5 miles of the user (Location Intelligence).
      if (layers.contains(MapLayer.locations))
        for (final p in places.where((p) => highlightedIds.contains(p.id)))
          Circle(
            circleId: CircleId('hl_${p.id}'),
            center: LatLng(p.latitude, p.longitude),
            radius: 160,
            strokeColor: _MapPalette.green,
            strokeWidth: 2,
            fillColor: _MapPalette.green.withValues(alpha: 0.12),
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
                  clusterManagers: {
                    ClusterManager(
                      clusterManagerId: _placesCluster,
                      onClusterTap: _onClusterTap,
                    ),
                  },
                  mapType: MapType.hybrid,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  onTap: (_) {
                    if (_selection != null) {
                      setState(() => _selection = null);
                    }
                  },
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
                if (_selection == null) _aroundMeButton(hits.length),
                if (_banner != null) _bannerOverlay(),
                if (_selection != null) _selectionCard(userLocation),
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

  void _goToLocation(MasterLocation l) {
    if (l.latitude == null || l.longitude == null) return;
    final pos = LatLng(l.latitude!, l.longitude!);
    ref.read(mapCenterProvider.notifier).set(pos);
    // Zoom in past the clustering threshold so the marker is individually
    // visible (not merged into a cluster).
    _controller?.animateCamera(CameraUpdate.newLatLngZoom(pos, 15));
  }

  void _openSearch() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _MapPalette.header,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _LocationSearchSheet(onPick: (l) {
          Navigator.of(context).pop();
          _goToLocation(l);
          showDestinationDetail(context, l);
        }),
      ),
    );
  }

  void _openCategoryFilter() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _MapPalette.header,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Consumer(builder: (context, ref, _) {
        final active = ref.watch(mapCategoryFilterProvider);
        final notifier = ref.read(mapCategoryFilterProvider.notifier);
        final allShown = active.length == markerLegend.length;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Show on map',
                          style: TextStyle(
                              color: _MapPalette.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                    ),
                    TextButton(
                      onPressed: notifier.showAll,
                      child: Text(allShown ? 'All shown' : 'Show all'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final s in markerLegend)
                      FilterChip(
                        avatar: Icon(s.icon,
                            size: 16,
                            color:
                                active.contains(s.key) ? Colors.white : s.color),
                        label: Text(s.label),
                        selected: active.contains(s.key),
                        selectedColor: s.color,
                        backgroundColor: _MapPalette.control,
                        labelStyle: TextStyle(
                            color: active.contains(s.key)
                                ? Colors.white
                                : _MapPalette.textSecondary,
                            fontSize: 12),
                        onSelected: (_) => notifier.toggle(s.key),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      }),
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
              tooltip: 'Search locations',
              onPressed: _openSearch,
              icon: const Icon(Icons.search_rounded,
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
              tooltip: 'Filter categories',
              onPressed: _openCategoryFilter,
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

  /// The bottom information card for the selected marker: photo, name, category,
  /// distance, and Listen / Navigate / Save / More Info actions. Animates in.
  Widget _selectionCard(LatLng? userLocation) {
    final sel = _selection!;
    final distance = userLocation != null
        ? formatDistance(_metersBetween(userLocation, sel.position))
        : null;
    // Sit above the shell's floating NavigationBar (extendBody makes the map
    // flow underneath it): bar height (68) + its bottom padding + safe area.
    final bottomInset = MediaQuery.of(context).padding.bottom + 68 + 24;
    return Positioned(
      left: AppSpacing.md,
      right: AppSpacing.md,
      bottom: bottomInset,
      child: TweenAnimationBuilder<double>(
        key: ValueKey(sel.markerId),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Opacity(
          opacity: t.clamp(0, 1),
          child: Transform.translate(offset: Offset(0, (1 - t) * 18), child: child),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: _MapPalette.control,
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: sel.style.color.withValues(alpha: 0.6)),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x88000000), blurRadius: 18, offset: Offset(0, 6))
            ],
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: AppRadius.mdAll,
                    child: SizedBox(
                      width: 60,
                      height: 60,
                      child: (sel.imageUrl != null && sel.imageUrl!.isNotEmpty)
                          ? Image.network(sel.imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => _thumbFallback(sel))
                          : _thumbFallback(sel),
                    ),
                  ),
                  const Gap.h(AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(sel.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: _MapPalette.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w800)),
                        const Gap.v(4),
                        Row(
                          children: [
                            Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                    color: sel.style.color,
                                    shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(sel.style.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: _MapPalette.textSecondary,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600)),
                            ),
                            if (distance != null) ...[
                              const Text('  ·  ',
                                  style:
                                      TextStyle(color: _MapPalette.textSecondary)),
                              Text(distance,
                                  style: const TextStyle(
                                      color: _MapPalette.gold,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _selection = null),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded,
                        color: _MapPalette.textSecondary),
                  ),
                ],
              ),
              const Gap.v(AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _listen(sel),
                      style: FilledButton.styleFrom(
                          backgroundColor: _MapPalette.gold,
                          foregroundColor: Colors.black,
                          minimumSize: const Size(0, 42)),
                      icon: const Icon(Icons.podcasts_rounded, size: 18),
                      label: const Text('Listen', overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const Gap.h(AppSpacing.sm),
                  _cardIconButton(
                      Icons.navigation_rounded, 'Navigate', () => _navigateTo(sel)),
                  const Gap.h(AppSpacing.sm),
                  _cardIconButton(
                      Icons.bookmark_border_rounded,
                      'Save',
                      () => ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Saved ${sel.name}')))),
                  const Gap.h(AppSpacing.sm),
                  _cardIconButton(Icons.info_outline_rounded, 'More Info',
                      () => _moreInfo(sel, distance)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbFallback(_MapSelection sel) => Container(
        color: sel.style.color.withValues(alpha: 0.22),
        child: Icon(sel.style.icon, color: sel.style.color, size: 26),
      );

  Widget _cardIconButton(IconData icon, String tooltip, VoidCallback onTap) =>
      Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.white.withValues(alpha: 0.10),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.mdAll,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: InkWell(
            borderRadius: AppRadius.mdAll,
            onTap: onTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 52,
                  height: 42,
                  child: Icon(icon, size: 20, color: _MapPalette.textPrimary),
                ),
              ],
            ),
          ),
        ),
      );
}

/// The data behind the selected-marker info card.
class _MapSelection {
  const _MapSelection({
    required this.markerId,
    required this.name,
    required this.style,
    required this.position,
    this.imageUrl,
    this.audioUrl,
    this.park,
  });

  final String markerId;
  final String name;
  final MarkerCategoryStyle style;
  final LatLng position;
  final String? imageUrl;
  final String? audioUrl;
  final Destination? park;
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

/// Global location search over the master `locations` database. Typing filters
/// live via [LocationEngine.search]; picking a result recenters + zooms the map.
class _LocationSearchSheet extends ConsumerStatefulWidget {
  const _LocationSearchSheet({required this.onPick});
  final void Function(MasterLocation) onPick;
  @override
  ConsumerState<_LocationSearchSheet> createState() =>
      _LocationSearchSheetState();
}

class _LocationSearchSheetState extends ConsumerState<_LocationSearchSheet> {
  final _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(masterLocationsProvider).value ?? const [];
    final results = _q.trim().isEmpty
        ? const <MasterLocation>[]
        : ref.read(locationEngineProvider).search(_q, all, limit: 30);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              style: const TextStyle(color: _MapPalette.textPrimary),
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: 'Search locations (e.g. Lake Bryant)…',
                hintStyle: const TextStyle(color: _MapPalette.textSecondary),
                prefixIcon:
                    const Icon(Icons.search_rounded, color: _MapPalette.textSecondary),
                filled: true,
                fillColor: _MapPalette.control,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_q.trim().isNotEmpty && results.isEmpty)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Text('No matching locations.',
                    style: TextStyle(color: _MapPalette.textSecondary)),
              ),
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: results.length,
                itemBuilder: (_, i) {
                  final l = results[i];
                  final ready = l.isReady;
                  return ListTile(
                    leading: Icon(
                      ready ? Icons.check_circle_rounded : Icons.mic_off_rounded,
                      color: ready
                          ? _MapPalette.green
                          : _MapPalette.textSecondary,
                    ),
                    title: Text(l.name,
                        style: const TextStyle(color: _MapPalette.textPrimary)),
                    subtitle: Text(
                      [l.type.label, l.placeLine].whereType<String>().join(' · '),
                      style: const TextStyle(color: _MapPalette.textSecondary),
                    ),
                    trailing: const Icon(Icons.my_location_rounded,
                        color: _MapPalette.gold),
                    onTap: () => widget.onPick(l),
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
