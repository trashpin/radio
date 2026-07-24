/// Enumerations used throughout the GPS Intelligence Engine.
library;

/// How the user is travelling, inferred from speed.
enum TravelMode { walking, driving, biking, stationary }

/// The user's relationship to a destination/park over time.
enum ArrivalStatus { approaching, arrived, visiting, departing, left }

/// Whether the user is currently in motion.
enum MovementState { moving, stopped, idle }

/// Lifecycle status of the tracking engine itself.
enum GpsTrackingStatus { idle, tracking, paused, stopped }

/// Which underlying positioning provider is in use. This prepares the engine
/// for multiple providers (system geolocation, Google, Apple, offline/downloaded
/// maps) — swapped behind the `LocationProvider` interface.
enum GpsProviderType { simulated, system, google, apple, offline }

/// Eight-point compass direction, derived from a bearing in degrees.
enum CardinalDirection {
  north,
  northEast,
  east,
  southEast,
  south,
  southWest,
  west,
  northWest;

  /// Maps a 0–360° bearing to the nearest compass point.
  static CardinalDirection fromBearing(double bearingDegrees) {
    final normalized = (bearingDegrees % 360 + 360) % 360;
    const values = CardinalDirection.values;
    final index = ((normalized + 22.5) ~/ 45) % 8;
    return values[index];
  }
}
