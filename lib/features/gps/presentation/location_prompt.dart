import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/gps/models/gps_status.dart';
import 'package:explorer_os_mobile/features/gps/providers/gps_status_provider.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';

/// A slim, self-contained banner that makes the "no location yet" state
/// actionable on the main user screens, so nearby/radio/discover never sit
/// silently empty. It disappears the moment the app has a location
/// ([mapCenterProvider] != null), and otherwise offers the right one-tap
/// recovery for the current permission state:
///   • permission never asked / denied → "Enable location" (prompts)
///   • permanently denied / GPS off     → "Open settings"
///   • granted but no fix yet           → spinner + "Retry"
///
/// Self-styled (doesn't depend on the host screen's theme colors) so it reads
/// well on the light Around Me screen and the dark Radio/Explore backgrounds.
class LocationPrompt extends ConsumerWidget {
  const LocationPrompt({super.key, this.margin});

  final EdgeInsetsGeometry? margin;

  static const _accent = Color(0xFFE0A458);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Once we have a center, nearby/radio/discover all work — hide entirely.
    if (ref.watch(mapCenterProvider) != null) return const SizedBox.shrink();

    final gps = ref.watch(gpsStatusProvider);
    final perm = gps.permission;
    final needsSettings = perm == LocationPermissionStatus.deniedForever ||
        perm == LocationPermissionStatus.serviceDisabled;
    final searching = gps.isGranted; // permission fine, just no fix yet

    final String title;
    final String body;
    final String action;
    if (searching) {
      title = 'Finding your location…';
      body = "Make sure GPS is on and you're outdoors. Tap retry if it's "
          'taking a while.';
      action = 'Retry';
    } else if (needsSettings) {
      title = 'Location is turned off';
      body = 'ExplorerOS needs your location to show what\'s around you. '
          'Turn it back on in Settings.';
      action = 'Open settings';
    } else {
      title = 'Turn on location';
      body = 'ExplorerOS uses your location to surface nearby places, stories '
          'and radio as you travel.';
      action = 'Enable location';
    }

    void onTap() {
      final n = ref.read(gpsStatusProvider.notifier);
      if (needsSettings) {
        n.openSettings();
        n.refreshPermission();
      } else {
        n.requestAndStart();
      }
    }

    return Padding(
      padding: margin ?? const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _accent.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: searching
                  ? const Padding(
                      padding: EdgeInsets.all(4),
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: _accent),
                    )
                  : const Icon(Icons.location_off_rounded,
                      color: _accent, size: 30),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: Color(0xFF1A1A1A)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: const TextStyle(
                        fontSize: 12.5, color: Color(0xFF5A5A5A), height: 1.3),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: onTap,
                      icon: Icon(
                          needsSettings
                              ? Icons.settings_rounded
                              : Icons.my_location_rounded,
                          size: 18),
                      label: Text(action),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
