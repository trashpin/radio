import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/destinations/providers/destinations_provider.dart';
import 'package:explorer_os_mobile/features/maps/providers/map_layers_provider.dart';
import 'package:explorer_os_mobile/features/sightings/providers/sighting_providers.dart';
import 'package:explorer_os_mobile/shared/models/destination.dart';

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
  LatLng _center = MapsScreen._fallbackCenter;

  @override
  void initState() {
    super.initState();
    _buildIcons();
  }

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
      if (mounted) {
        setState(() {
          _pinIcon = pin;
          _locationIcon = location;
          _sightingIcon = sighting;
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

  double _distanceMiles(LatLng a, LatLng b) {
    const earthKm = 6371.0;
    final dLat = _rad(b.latitude - a.latitude);
    final dLng = _rad(b.longitude - a.longitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(a.latitude)) *
            math.cos(_rad(b.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final km = earthKm * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return km * 0.621371;
  }

  double _rad(double deg) => deg * math.pi / 180;

  Destination? _nearest(List<Destination> mappable) {
    if (mappable.isEmpty) return null;
    mappable.sort((a, b) => _distanceMiles(_center, LatLng(a.latitude!, a.longitude!))
        .compareTo(_distanceMiles(_center, LatLng(b.latitude!, b.longitude!))));
    return mappable.first;
  }

  @override
  Widget build(BuildContext context) {
    final destinations = ref.watch(destinationsProvider).value ?? const [];
    final mappable =
        destinations.where((d) => d.hasCoordinates).toList(growable: false);
    final sightings = ref.watch(recentSightingsProvider).value ?? const [];
    final stops = ref.watch(allStopsProvider).value ?? const [];
    final layers = ref.watch(mapLayersProvider);

    final markers = <Marker>{
      if (layers.contains(MapLayer.parks))
        for (final d in mappable)
          Marker(
            markerId: MarkerId('park_${d.id}'),
            position: LatLng(d.latitude!, d.longitude!),
            icon: _pinIcon ?? BitmapDescriptor.defaultMarker,
            infoWindow: InfoWindow(title: d.name, snippet: d.location),
          ),
      if (layers.contains(MapLayer.locations))
        for (final s in stops.where((s) => s.latitude != null && s.longitude != null))
          Marker(
            markerId: MarkerId('stop_${s.id}'),
            position: LatLng(s.latitude!, s.longitude!),
            icon: _locationIcon ??
                BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueAzure),
            infoWindow: InfoWindow(
                title: s.name, snippet: s.stopType ?? 'Location'),
          ),
      if (layers.contains(MapLayer.sightings))
        for (final s in sightings.where((s) => s.hasCoordinates))
          Marker(
            markerId: MarkerId('sighting_${s.id}'),
            position: LatLng(s.latitude!, s.longitude!),
            icon: _sightingIcon ??
                BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueOrange),
            infoWindow: InfoWindow(
              title: s.species ?? s.category.label,
              snippet: 'Sighting · ${s.category.label}',
            ),
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
    };

    final initialTarget = mappable.isNotEmpty
        ? LatLng(mappable.first.latitude!, mappable.first.longitude!)
        : MapsScreen._fallbackCenter;
    final nearest = _nearest([...mappable]);

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
                  onCameraMove: (pos) => _center = pos.target,
                  onCameraIdle: () => setState(() {}),
                ),
                _controls(initialTarget),
                _layerChips(layers),
                if (nearest != null)
                  _NearestCard(
                    destination: nearest,
                    miles: _distanceMiles(
                        _center, LatLng(nearest.latitude!, nearest.longitude!)),
                  ),
              ],
            ),
          ),
        ],
      ),
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

  Widget _controls(LatLng recenterTarget) {
    return Positioned(
      top: AppSpacing.lg,
      right: AppSpacing.lg,
      child: Column(
        children: [
          _controlButton(
            Icons.near_me_rounded,
            () => _controller?.animateCamera(
                CameraUpdate.newLatLngZoom(recenterTarget, 9)),
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

/// Bottom card showing the destination nearest the current map center.
class _NearestCard extends StatelessWidget {
  const _NearestCard({required this.destination, required this.miles});

  final Destination destination;
  final double miles;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: AppSpacing.lg,
      right: AppSpacing.lg,
      bottom: 96,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: _MapPalette.control,
          borderRadius: AppRadius.lgAll,
          boxShadow: const [
            BoxShadow(
                color: Color(0x66000000),
                blurRadius: 20,
                offset: Offset(0, 8)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: _MapPalette.green,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.park_rounded,
                  color: Colors.white, size: 22),
            ),
            const Gap.h(AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    destination.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: _MapPalette.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                  ),
                  Text(
                    destination.location ?? destination.category ?? 'Destination',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: _MapPalette.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Gap.h(AppSpacing.sm),
            Text(
              '${miles.toStringAsFixed(miles < 10 ? 1 : 0)} mi',
              style: const TextStyle(
                  color: _MapPalette.gold,
                  fontSize: 13,
                  fontWeight: FontWeight.w700),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: _MapPalette.textSecondary),
          ],
        ),
      ),
    );
  }
}
