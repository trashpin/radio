import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/navigation/providers/trip_provider.dart';

/// A small "Start Trip" action placed ALONGSIDE (never replacing) an
/// existing "Navigate" button — per the user's own decision: external Maps
/// remains the visual navigation experience; this just also hands the
/// destination to the background `TripTracker` so the Travel Copilot can
/// narrate the drive. See lib/features/navigation/.
class StartTripButton extends ConsumerWidget {
  const StartTripButton({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.name,
  });

  final double latitude;
  final double longitude;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(tripControllerProvider).isActive;
    return OutlinedButton.icon(
      onPressed: active
          ? null
          : () => ref.read(tripControllerProvider.notifier).startTrip(
                lat: latitude,
                lng: longitude,
                name: name,
              ),
      icon: const Icon(Icons.navigation_outlined, size: 18),
      label: Text(active ? 'Trip Active' : 'Start Trip'),
    );
  }
}
