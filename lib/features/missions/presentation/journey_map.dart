import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/missions/controllers/active_mission_controller.dart';
import 'package:explorer_os_mobile/features/missions/controllers/mission_route_controller.dart';
import 'package:explorer_os_mobile/features/missions/services/journey_nearby_locations.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';

const double _mile = 1609.344;
const double _foot = 0.3048;

String _friendlyDistance(double meters) {
  final miles = meters / _mile;
  if (miles >= 0.25) return '${miles.toStringAsFixed(1)} mi';
  final feet = (meters / _foot).round();
  return '$feet ft';
}

String _friendlyDuration(int seconds) {
  final minutes = (seconds / 60).round();
  if (minutes < 1) return '<1 min';
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rem = minutes % 60;
  return rem == 0 ? '${hours}h' : '${hours}h ${rem}min';
}

/// The Marion County Adventures journey map — a real, interactive map
/// showing where the player is, where they're going, the real driving
/// route between them, and a handful of relevant existing locations along
/// the way. Reuses `google_maps_flutter` (the same package the app's main
/// Explore Map already uses), the same live GPS stream
/// ([gpsControllerProvider]) every location-aware feature reads, and the
/// same [TripTracker]/Directions integration `StartTripButton`'s existing
/// navigation feature already uses (via [MissionRouteController], a
/// separate instance so the two features never collide) — no new mapping
/// or routing technology.
///
/// Deliberately does NOT touch [ActiveMissionController]/
/// [MissionStoryEngine] — it only ever READS `currentStop`/
/// `lastDistanceMeters`/`awaitingQr` from them. The story engine keeps
/// using its own straight-line distance for trigger timing, unchanged;
/// this map's own distance/ETA readout uses the real driving route, a
/// nicer number for DISPLAY only.
class JourneyMap extends ConsumerStatefulWidget {
  const JourneyMap({super.key});

  @override
  ConsumerState<JourneyMap> createState() => _JourneyMapState();
}

class _JourneyMapState extends ConsumerState<JourneyMap> {
  GoogleMapController? _mapController;
  bool _autoFollow = true;
  bool _programmaticMove = false;
  LatLng? _lastFitPlayer;
  String? _lastRoutedStopId;

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  void _maybeStartRoute(String stopId, double lat, double lng, String name) {
    if (_lastRoutedStopId == stopId) return;
    _lastRoutedStopId = stopId;
    _autoFollow = true;
    _lastFitPlayer = null;
    ref.read(missionRouteControllerProvider.notifier).routeTo(lat: lat, lng: lng, name: name);
  }

  Future<void> _fitCamera(LatLng player, LatLng destination) async {
    final controller = _mapController;
    if (controller == null) return;
    _programmaticMove = true;
    final bounds = LatLngBounds(
      southwest: LatLng(
        player.latitude < destination.latitude ? player.latitude : destination.latitude,
        player.longitude < destination.longitude ? player.longitude : destination.longitude,
      ),
      northeast: LatLng(
        player.latitude > destination.latitude ? player.latitude : destination.latitude,
        player.longitude > destination.longitude ? player.longitude : destination.longitude,
      ),
    );
    try {
      await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 72));
    } catch (_) {
      // A degenerate (single-point) bounds throws on some platforms —
      // fall back to a plain recenter on the player instead.
      await controller.animateCamera(CameraUpdate.newLatLngZoom(player, 15));
    }
    _lastFitPlayer = player;
    _programmaticMove = false;
  }

  void _recenter(LatLng player, LatLng destination) {
    setState(() => _autoFollow = true);
    _fitCamera(player, destination);
  }

  @override
  Widget build(BuildContext context) {
    final missionState = ref.watch(activeMissionControllerProvider);
    final stop = missionState.currentStop;
    final gpsLoc = ref.watch(gpsControllerProvider).location;

    if (stop == null) {
      return const _MapMessage(text: 'Loading your adventure...');
    }

    final destination = LatLng(stop.latitude, stop.longitude);
    if (gpsLoc != null) {
      _maybeStartRoute(stop.id, stop.latitude, stop.longitude, stop.title);
    }

    final player = gpsLoc == null ? null : LatLng(gpsLoc.latitude, gpsLoc.longitude);
    final routeState = ref.watch(missionRouteControllerProvider);

    // Auto-follow: refit only when the player has moved meaningfully since
    // the last fit, or we haven't fit yet — never on every GPS jitter.
    if (player != null && _autoFollow) {
      final moved = _lastFitPlayer == null ||
          GeoMath.distanceMeters(
                _lastFitPlayer!.latitude,
                _lastFitPlayer!.longitude,
                player.latitude,
                player.longitude,
              ) >
              120;
      if (moved) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _fitCamera(player, destination));
      }
    }

    final nearby = player == null
        ? const <MasterLocation>[]
        : ref.watch(journeyNearbyLocationsProvider((
            playerLat: player.latitude,
            playerLng: player.longitude,
            destLat: destination.latitude,
            destLng: destination.longitude,
            excludeLocationId: stop.locationId,
          )));

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('destination'),
        position: destination,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(title: 'NEXT DISCOVERY', snippet: stop.title),
        zIndexInt: 2,
      ),
      if (player != null)
        Marker(
          markerId: const MarkerId('player'),
          position: player,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'You'),
          zIndexInt: 3,
        ),
      for (final loc in nearby)
        Marker(
          markerId: MarkerId('nearby-${loc.id}'),
          position: LatLng(loc.latitude!, loc.longitude!),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          infoWindow: InfoWindow(title: loc.name, snippet: loc.type.label),
          zIndexInt: 1,
        ),
    };

    final polylinePoints = routeState.route?.overviewPolyline ?? const [];
    final polylines = <Polyline>{
      if (polylinePoints.length >= 2)
        Polyline(
          polylineId: const PolylineId('journey'),
          points: [for (final p in polylinePoints) LatLng(p.lat, p.lng)],
          color: RD.green,
          width: 5,
        ),
    };

    return ClipRRect(
      borderRadius: RD.brLg,
      child: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: player ?? destination,
              zoom: 13,
            ),
            markers: markers,
            polylines: polylines,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            onMapCreated: (c) => _mapController = c,
            onCameraMoveStarted: () {
              if (!_programmaticMove) _autoFollow = false;
            },
          ),
          // CURRENT ADVENTURE / MISSION PROGRESS / NEXT DISCOVERY — the game
          // board's header, top of the map, always visible.
          Positioned(
            left: RD.md,
            right: RD.md,
            top: RD.md,
            child: _Pill(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if ((missionState.mission?.title ?? '').isNotEmpty)
                    Row(children: [
                      Expanded(
                        child: Text(missionState.mission!.title.toUpperCase(),
                            style: const TextStyle(
                                color: RD.green, fontSize: 11, fontWeight: FontWeight.w800),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (missionState.stops.isNotEmpty)
                        Text('STOP ${stop.sequence} OF ${missionState.stops.length}',
                            style: const TextStyle(color: Colors.white54, fontSize: 10)),
                    ]),
                  const SizedBox(height: 2),
                  Text('NEXT DISCOVERY', style: RD.sectionLabel.copyWith(fontSize: 11)),
                  Text(stop.title,
                      style: RD.cardTitle.copyWith(color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ),
          // Distance / proximity readout — bottom of the map.
          Positioned(
            left: RD.md,
            right: RD.md,
            bottom: RD.md,
            child: _DistanceReadout(
              awaitingQr: missionState.awaitingQr,
              storyDistanceMeters: missionState.lastDistanceMeters,
              routeDistanceMeters: routeState.route?.totalDistanceMeters,
              routeDurationSeconds: routeState.route?.totalDurationSeconds,
            ),
          ),
          if (player != null)
            Positioned(
              right: RD.md,
              bottom: 96,
              child: _RecenterButton(onPressed: () => _recenter(player, destination)),
            ),
        ],
      ),
    );
  }
}

class _MapMessage extends StatelessWidget {
  const _MapMessage({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: RD.brLg,
      child: Container(
        color: RD.panel,
        alignment: Alignment.center,
        child: Text(text, style: RD.body),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: RD.md, vertical: RD.sm),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(RD.rMd),
      ),
      child: child,
    );
  }
}

/// "DISTANCE TO DISCOVERY" — driver-friendly: one clear number, high
/// contrast, plus the adventure-flavored proximity language the spec asks
/// for instead of navigation-app wording. Prefers the real road distance/
/// ETA (from Directions) when available; falls back to the straight-line
/// distance the mission engine already tracks so something always shows,
/// even before a route has finished fetching.
class _DistanceReadout extends StatelessWidget {
  const _DistanceReadout({
    required this.awaitingQr,
    required this.storyDistanceMeters,
    required this.routeDistanceMeters,
    required this.routeDurationSeconds,
  });

  final bool awaitingQr;
  final double? storyDistanceMeters;
  final double? routeDistanceMeters;
  final int? routeDurationSeconds;

  @override
  Widget build(BuildContext context) {
    if (awaitingQr) {
      return _Pill(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.explore_rounded, color: RD.green, size: 22),
          const SizedBox(width: RD.sm),
          Text("YOU'VE ARRIVED - ADVENTURE LOCATION",
              style: RD.cardTitle.copyWith(color: RD.green, fontSize: 14)),
        ]),
      );
    }

    final distanceMeters = routeDistanceMeters ?? storyDistanceMeters;
    if (distanceMeters == null) {
      return const _Pill(
        child: Text('Waiting for GPS...', style: TextStyle(color: Colors.white70)),
      );
    }

    final proximity = _proximityLabel(distanceMeters);

    return _Pill(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('DISTANCE TO DISCOVERY',
                  style: TextStyle(
                      color: RD.textSecondary, fontSize: 10, fontWeight: FontWeight.w700)),
              Row(children: [
                Text(_friendlyDistance(distanceMeters),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                if (routeDurationSeconds != null) ...[
                  const SizedBox(width: RD.sm),
                  Text('· ~${_friendlyDuration(routeDurationSeconds!)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ]),
            ],
          ),
          if (proximity != null) ...[
            const SizedBox(width: RD.md),
            Expanded(
              child: Text(proximity,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                      color: RD.green, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }

  String? _proximityLabel(double meters) {
    if (meters <= 500) return "YOUR DISCOVERY\nIS NEARBY";
    if (meters <= 1609) return "YOU'RE GETTING\nCLOSE";
    return null;
  }
}

class _RecenterButton extends StatelessWidget {
  const _RecenterButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: 'Recenter',
        onPressed: onPressed,
        icon: const Icon(Icons.my_location_rounded, color: Colors.white),
      ),
    );
  }
}
