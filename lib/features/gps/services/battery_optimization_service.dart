import 'package:explorer_os_mobile/features/gps/models/gps_enums.dart';

/// A recommended sampling policy for the location provider.
class LocationSamplingPolicy {
  const LocationSamplingPolicy({
    required this.interval,
    required this.distanceFilterMeters,
  });

  /// How often to request a fix.
  final Duration interval;

  /// Minimum movement before a new fix is emitted.
  final double distanceFilterMeters;
}

/// Recommends how aggressively to sample location to preserve battery.
///
/// WHY THIS EXISTS: continuous high-frequency GPS is the biggest battery drain
/// in a travel app. This policy service maps the user's movement/travel mode to
/// a sensible sampling cadence + distance filter, which a real [LocationProvider]
/// adapter applies. Stationary users get sparse updates; drivers get frequent
/// ones. Keeping the policy here (not in the provider) makes it tunable and
/// testable without a device.
class BatteryOptimizationService {
  const BatteryOptimizationService();

  LocationSamplingPolicy recommend(
    MovementState movement,
    TravelMode mode,
  ) {
    if (movement != MovementState.moving) {
      // Stopped/idle: sample rarely with a large filter.
      return const LocationSamplingPolicy(
        interval: Duration(seconds: 30),
        distanceFilterMeters: 50,
      );
    }
    switch (mode) {
      case TravelMode.driving:
        return const LocationSamplingPolicy(
          interval: Duration(seconds: 2),
          distanceFilterMeters: 20,
        );
      case TravelMode.biking:
        return const LocationSamplingPolicy(
          interval: Duration(seconds: 4),
          distanceFilterMeters: 15,
        );
      case TravelMode.walking:
        return const LocationSamplingPolicy(
          interval: Duration(seconds: 6),
          distanceFilterMeters: 10,
        );
      case TravelMode.stationary:
        return const LocationSamplingPolicy(
          interval: Duration(seconds: 30),
          distanceFilterMeters: 50,
        );
    }
  }
}
