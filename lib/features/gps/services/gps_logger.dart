import 'package:flutter/foundation.dart';

import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';

/// The kinds of structured GPS lifecycle events we log.
enum GpsLogKind {
  permissionRequested,
  permissionGranted,
  permissionDenied,
  initialized,
  locationUpdated,
  gpsLost,
  gpsRestored,
  subscriptionStarted,
  subscriptionStopped,
  error,
}

/// A single structured log line.
class GpsLogEntry {
  GpsLogEntry(this.kind, this.message, {DateTime? at})
      : at = at ?? DateTime.now();

  final GpsLogKind kind;
  final String message;
  final DateTime at;

  @override
  String toString() {
    final t = at.toIso8601String().substring(11, 19);
    return '$t  ${kind.name}${message.isEmpty ? '' : ' · $message'}';
  }
}

/// A tiny structured logger for the GPS flow.
///
/// Keeps a bounded ring buffer of recent events (for the debug screen), counts
/// received location updates, and mirrors each line to the console. It holds no
/// audio and makes no decisions — purely observability.
class GpsLogger {
  GpsLogger({this.capacity = 100});

  final int capacity;
  final List<GpsLogEntry> _entries = [];
  int _updateCount = 0;

  List<GpsLogEntry> get entries => List.unmodifiable(_entries);
  GpsLogEntry? get lastEntry => _entries.isEmpty ? null : _entries.last;

  /// Number of location fixes received since the logger was created/cleared.
  int get updateCount => _updateCount;

  void log(GpsLogKind kind, [String message = '']) {
    if (kind == GpsLogKind.locationUpdated) _updateCount++;
    final entry = GpsLogEntry(kind, message);
    _entries.add(entry);
    if (_entries.length > capacity) {
      _entries.removeRange(0, _entries.length - capacity);
    }
    if (kDebugMode) debugPrint('[GPS] $entry');
  }

  // Convenience wrappers for the well-known events.
  void permissionRequested() => log(GpsLogKind.permissionRequested);
  void permissionGranted(String detail) =>
      log(GpsLogKind.permissionGranted, detail);
  void permissionDenied(String detail) =>
      log(GpsLogKind.permissionDenied, detail);
  void initialized() => log(GpsLogKind.initialized);
  void subscriptionStarted() => log(GpsLogKind.subscriptionStarted);
  void subscriptionStopped() => log(GpsLogKind.subscriptionStopped);
  void gpsLost(String reason) => log(GpsLogKind.gpsLost, reason);
  void gpsRestored() => log(GpsLogKind.gpsRestored);
  void error(String message) => log(GpsLogKind.error, message);

  void locationUpdated(GPSLocation fix) => log(
        GpsLogKind.locationUpdated,
        '${fix.latitude.toStringAsFixed(5)}, '
            '${fix.longitude.toStringAsFixed(5)} '
            '±${fix.accuracyMeters?.toStringAsFixed(0) ?? '?'}m',
      );

  void clear() {
    _entries.clear();
    _updateCount = 0;
  }
}
