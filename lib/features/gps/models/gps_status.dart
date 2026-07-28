/// The visitor's location-permission state, normalized across platforms.
enum LocationPermissionStatus {
  /// Not yet determined / not requested.
  unknown,

  /// The OS location service is turned off entirely (airplane mode / disabled).
  serviceDisabled,

  /// Permission was denied (can ask again).
  denied,

  /// Permission was permanently denied (must be changed in system settings).
  deniedForever,

  /// Granted while the app is in use (foreground).
  grantedWhenInUse,

  /// Granted at all times (background allowed).
  grantedAlways;

  bool get isGranted =>
      this == grantedWhenInUse || this == grantedAlways;

  /// A clear, user-facing message describing the state and what to do.
  String get message => switch (this) {
        LocationPermissionStatus.unknown => 'Checking location permission…',
        LocationPermissionStatus.serviceDisabled =>
          'Location services are turned off. Enable them in your device '
              'settings to see what\'s around you.',
        LocationPermissionStatus.denied =>
          'Location permission is needed to show nearby experiences. '
              'Tap to allow access.',
        LocationPermissionStatus.deniedForever =>
          'Location permission is blocked. Open settings to allow ExplorerOS '
              'to access your location.',
        LocationPermissionStatus.grantedWhenInUse =>
          'Location access granted.',
        LocationPermissionStatus.grantedAlways =>
          'Location access granted (always).',
      };
}

/// An app-wide, immutable snapshot of the live GPS state.
///
/// This is the single surface every system (Around Me, Playback Manager,
/// Experience Intelligence, Explorer Radio) can read to know where the visitor
/// is right now, how accurate the fix is, and whether tracking is healthy.
class GpsStatus {
  const GpsStatus({
    this.permission = LocationPermissionStatus.unknown,
    this.serviceEnabled = false,
    this.tracking = false,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.headingDegrees,
    this.speedMps,
    this.altitudeMeters,
    this.lastUpdate,
    this.updateCount = 0,
  });

  final LocationPermissionStatus permission;
  final bool serviceEnabled;
  final bool tracking;

  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final double? headingDegrees;
  final double? speedMps;
  final double? altitudeMeters;

  final DateTime? lastUpdate;

  /// How many fixes have been received since tracking began.
  final int updateCount;

  bool get hasFix => latitude != null && longitude != null;
  bool get isGranted => permission.isGranted;
  double get speedMph => (speedMps ?? 0) * 2.2369362921;

  factory GpsStatus.initial() => const GpsStatus();

  GpsStatus copyWith({
    LocationPermissionStatus? permission,
    bool? serviceEnabled,
    bool? tracking,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    double? headingDegrees,
    double? speedMps,
    double? altitudeMeters,
    DateTime? lastUpdate,
    int? updateCount,
  }) {
    return GpsStatus(
      permission: permission ?? this.permission,
      serviceEnabled: serviceEnabled ?? this.serviceEnabled,
      tracking: tracking ?? this.tracking,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      headingDegrees: headingDegrees ?? this.headingDegrees,
      speedMps: speedMps ?? this.speedMps,
      altitudeMeters: altitudeMeters ?? this.altitudeMeters,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      updateCount: updateCount ?? this.updateCount,
    );
  }
}
