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
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';
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
  final Map<String, BitmapDescriptor> _categoryIcons = {};
  bool _centerInitialized = false;

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

  BitmapDescriptor _iconFor(String category) =>
      _categoryIcons[category] ??
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
      // Real-time "Around Me" discovery markers (from map_locations), within
      // the selected radius, one icon per category.
      for (final hit in hits)
        Marker(
          markerId: MarkerId('nearby_${hit.item.id}'),
          position: LatLng(hit.item.latitude, hit.item.longitude),
          icon: _iconFor(hit.item.category),
          onTap: () => _openNearbySheet(hit),
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
                  onMapCreated: (c) => _controller = c,
                ),
                _controls(initialTarget, userLocation),
                _layerChips(layers),
                _radiusSelector(radius),
                _aroundMeButton(hits.length),
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
      top: 150,
      right: AppSpacing.lg,
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
        ],
      ),
    );
  }

  Widget _controlButton(IconData icon, VoidCallback onTap) {
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
          child: Icon(icon, color: _MapPalette.textPrimary, size: 22),
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
