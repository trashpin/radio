import 'package:explorer_os_mobile/features/gps/models/location_snapshot.dart';

/// A rolling buffer of recent [LocationSnapshot]s.
///
/// WHY THIS EXISTS: to give the engine offline continuity (the last known
/// position/context survives signal loss) and a short history for "visited"
/// reasoning. In-memory with a capacity cap now; can be swapped for persistent
/// storage (for true offline/downloaded-park use) without changing callers.
class GPSCacheService {
  GPSCacheService({this.capacity = 200});

  final int capacity;
  final List<LocationSnapshot> _snapshots = [];

  List<LocationSnapshot> get history => List.unmodifiable(_snapshots);

  LocationSnapshot? get last => _snapshots.isEmpty ? null : _snapshots.last;

  void record(LocationSnapshot snapshot) {
    _snapshots.add(snapshot);
    if (_snapshots.length > capacity) {
      _snapshots.removeAt(0);
    }
  }

  void clear() => _snapshots.clear();
}
