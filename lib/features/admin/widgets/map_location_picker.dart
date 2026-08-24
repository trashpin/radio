import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Marion County's approximate center — the default view when no starting
/// coordinate is known yet.
const LatLng _kMarionCountyCenter = LatLng(29.1872, -82.1401);

/// A tap-to-place GPS coordinate picker, reused wherever an admin screen
/// needs real lat/lng (mission stops today; a natural next step for the
/// existing Locations/Geofence admin screens, which still take raw typed
/// numbers). Wraps the SAME `google_maps_flutter` package already used by
/// the traveler-facing map — no new mapping dependency.
///
/// Returns the picked [LatLng], or `null` if the admin cancelled.
Future<LatLng?> showMapLocationPicker(
  BuildContext context, {
  LatLng? initial,
  String title = 'Pick a location',
}) {
  return Navigator.of(context).push<LatLng>(
    MaterialPageRoute(
      builder: (_) => _MapLocationPickerScreen(initial: initial, title: title),
    ),
  );
}

class _MapLocationPickerScreen extends StatefulWidget {
  const _MapLocationPickerScreen({this.initial, required this.title});
  final LatLng? initial;
  final String title;

  @override
  State<_MapLocationPickerScreen> createState() => _MapLocationPickerScreenState();
}

class _MapLocationPickerScreenState extends State<_MapLocationPickerScreen> {
  late LatLng _picked = widget.initial ?? _kMarionCountyCenter;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _picked),
            child: const Text('Use this location', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.initial ?? _kMarionCountyCenter,
              zoom: widget.initial != null ? 15 : 11,
            ),
            markers: {
              Marker(
                markerId: const MarkerId('picked'),
                position: _picked,
                draggable: true,
                onDragEnd: (pos) => setState(() => _picked = pos),
              ),
            },
            onTap: (pos) => setState(() => _picked = pos),
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
            mapToolbarEnabled: false,
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  const Icon(Icons.pin_drop_rounded),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_picked.latitude.toStringAsFixed(6)}, ${_picked.longitude.toStringAsFixed(6)}',
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
