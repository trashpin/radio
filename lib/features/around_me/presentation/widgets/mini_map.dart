import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/features/around_me/models/experience.dart';
import 'package:explorer_os_mobile/features/around_me/providers/around_me_providers.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';

/// A compact live map that stays centered on the visitor and shows only nearby
/// items. Follows automatically; a temporary pan/zoom is respected, then it
/// re-centers on the visitor after a few seconds of inactivity.
class MiniMap extends ConsumerStatefulWidget {
  const MiniMap({super.key, this.height = 200});

  final double height;

  @override
  ConsumerState<MiniMap> createState() => _MiniMapState();
}

class _MiniMapState extends ConsumerState<MiniMap> {
  GoogleMapController? _controller;
  bool _following = true;
  Timer? _recenterTimer;
  LatLng? _last;

  @override
  void dispose() {
    _recenterTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  double get _zoom {
    switch (ref.read(searchRadiusProvider)) {
      case SearchRadius.ft100:
      case SearchRadius.ft250:
        return 17.5;
      case SearchRadius.ft500:
        return 16.5;
      case SearchRadius.mi025:
        return 15.5;
      case SearchRadius.mi05:
        return 15;
      case SearchRadius.mi1:
        return 14;
      case SearchRadius.mi2:
        return 13;
      case SearchRadius.mi5:
      case SearchRadius.entirePark:
        return 12;
    }
  }

  void _onUserGesture() {
    if (_following) setState(() => _following = false);
    _recenterTimer?.cancel();
    _recenterTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      setState(() => _following = true);
      final pos = _last;
      if (pos != null) {
        _controller?.animateCamera(CameraUpdate.newLatLngZoom(pos, _zoom));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(aroundMeControllerProvider);
    final experiences = ref.watch(aroundMeExperiencesProvider);
    final theme = Theme.of(context);

    final hasFix = snap.latitude != null && snap.longitude != null;
    final center = hasFix ? LatLng(snap.latitude!, snap.longitude!) : null;

    // Follow the visitor when a new fix arrives and we're in follow mode.
    if (center != null && _following && center != _last) {
      _last = center;
      _controller?.animateCamera(CameraUpdate.newLatLngZoom(center, _zoom));
    } else if (center != null) {
      _last = center;
    }

    return ClipRRect(
      borderRadius: AppRadius.lgAll,
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            if (center == null)
              _waiting(theme)
            else
              GoogleMap(
                initialCameraPosition:
                    CameraPosition(target: center, zoom: _zoom),
                onMapCreated: (c) {
                  _controller = c;
                  c.animateCamera(CameraUpdate.newLatLngZoom(center, _zoom));
                },
                onCameraMoveStarted: _onUserGesture,
                markers: _markers(center, experiences),
                circles: {
                  Circle(
                    circleId: const CircleId('me'),
                    center: center,
                    radius: 30,
                    fillColor: const Color(0x332F80ED),
                    strokeColor: const Color(0xFF2F80ED),
                    strokeWidth: 2,
                  ),
                },
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                compassEnabled: false,
                minMaxZoomPreference: const MinMaxZoomPreference(10, 19),
              ),
            Positioned(
              right: 8,
              bottom: 8,
              child: _followChip(),
            ),
          ],
        ),
      ),
    );
  }

  Set<Marker> _markers(LatLng center, List<Experience> experiences) {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('__me__'),
        position: center,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'You are here'),
        zIndexInt: 10,
      ),
    };
    for (final e in experiences.take(25)) {
      markers.add(Marker(
        markerId: MarkerId(e.id),
        position: LatLng(e.latitude, e.longitude),
        infoWindow: InfoWindow(title: e.name),
      ));
    }
    return markers;
  }

  Widget _followChip() {
    return Material(
      color: _following ? const Color(0xFF2F80ED) : Colors.white,
      borderRadius: AppRadius.pillAll,
      elevation: 2,
      child: InkWell(
        borderRadius: AppRadius.pillAll,
        onTap: () {
          setState(() => _following = true);
          _recenterTimer?.cancel();
          final pos = _last;
          if (pos != null) {
            _controller?.animateCamera(CameraUpdate.newLatLngZoom(pos, _zoom));
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.my_location_rounded,
                size: 14,
                color: _following ? Colors.white : const Color(0xFF2F80ED)),
            const SizedBox(width: 4),
            Text(_following ? 'Following' : 'Recenter',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _following ? Colors.white : const Color(0xFF2F80ED))),
          ]),
        ),
      ),
    );
  }

  Widget _waiting(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_searching_rounded,
                color: theme.disabledColor, size: 28),
            const SizedBox(height: 8),
            Text('Waiting for GPS…', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
