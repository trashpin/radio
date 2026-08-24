import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/missions/controllers/active_mission_controller.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_repository.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';

/// The physical QR marker scanner (spec Phase 4). Scanning never opens a
/// webpage — every successful scan is resolved against `qr_portals` and
/// acted on entirely inside [ActiveMissionController.onQrScanned], which
/// identifies the portal, confirms mission/stage ownership, verifies GPS
/// proximity, records the discovery, and awards XP before this screen ever
/// navigates anywhere.
///
/// Also offers a "Simulate Discovery" action: physical QR markers don't
/// need to exist yet for the full experience to be testable end to end
/// (spec: "provide a simulation mechanism ... without physical QR codes").
/// It resolves and submits the CURRENT stop's real code exactly as a
/// genuine scan would — not a shortcut that skips validation.
class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final raw = capture.barcodes.firstOrNull?.rawValue?.trim();
    if (raw == null || raw.isEmpty) return;
    await _controller.stop();
    await _submit(raw);
  }

  Future<void> _simulateDiscovery() async {
    final stop = ref.read(activeMissionControllerProvider).currentStop;
    final portalId = stop?.qrPortalId;
    if (portalId == null) {
      setState(() => _error = 'No QR marker is configured for this stop yet.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final portal = await ref.read(missionRepositoryProvider).portalById(portalId);
    if (portal == null) {
      setState(() {
        _busy = false;
        _error = 'This QR marker could not be found.';
      });
      return;
    }
    await _submit(portal.code);
  }

  Future<void> _submit(String code) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final loc = ref.read(gpsControllerProvider).location;
    final outcome = await ref.read(activeMissionControllerProvider.notifier).onQrScanned(
          code,
          lat: loc?.latitude,
          lng: loc?.longitude,
        );

    if (!mounted) return;
    if (outcome.success) {
      _navigateAfterSuccess(outcome);
    } else {
      setState(() {
        _busy = false;
        _error = outcome.message;
      });
      await _controller.start();
    }
  }

  /// A pending final puzzle always takes priority (it can exist whether or
  /// not this stop also has an Old World), then the Old World reveal, then
  /// outright completion, else back to the mission player.
  void _navigateAfterSuccess(QrScanOutcome outcome) {
    final hasPendingPuzzle = ref.read(activeMissionControllerProvider).hasPendingPuzzle;
    if (outcome.oldWorldId != null) {
      context.pushReplacement(
        AppRoute.oldWorld.oldWorldPathFor(outcome.oldWorldId!),
        extra: outcome.missionComplete ?? false,
      );
    } else if (hasPendingPuzzle) {
      context.pushReplacement(AppRoute.missionPuzzle.path);
    } else if (outcome.missionComplete ?? false) {
      context.pushReplacement(AppRoute.missionComplete.path);
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Find the QR Marker'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          _ScanFrame(),
          Positioned(
            left: RD.lg,
            right: RD.lg,
            bottom: RD.xl,
            child: Column(
              children: [
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: RD.md, vertical: RD.sm),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(RD.rPill),
                    ),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: RD.md),
                ],
                if (_busy)
                  const CircularProgressIndicator(color: Colors.white)
                else ...[
                  const Text(
                    'Look for a physical QR marker nearby and point your camera at it.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: RD.md),
                  OutlinedButton.icon(
                    onPressed: _simulateDiscovery,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                    icon: const Icon(Icons.science_outlined, size: 18),
                    label: const Text('Simulate Discovery (no marker needed yet)'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A simple decorative viewfinder square — purely visual, no scan logic.
class _ScanFrame extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 260,
        height: 260,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white70, width: 2),
          borderRadius: BorderRadius.circular(RD.rLg),
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
