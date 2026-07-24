import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/services/gps_cache_service.dart';

/// Provides last-known-location continuity when live positioning is unavailable.
///
/// WHY THIS EXISTS: in the backcountry (or with downloaded parks and no signal)
/// the engine should still expose a plausible position. This service reads the
/// most recent cached fix from [GPSCacheService] so `getCurrentLocation()` and
/// downstream reasoning degrade gracefully offline. A future implementation can
/// also serve fixes from an offline-map provider behind the same method.
class OfflineLocationService {
  const OfflineLocationService(this._cache);

  final GPSCacheService _cache;

  /// The most recent cached fix, if any.
  GPSLocation? lastKnownLocation() => _cache.last?.location;

  /// Whether we currently have a cached position to fall back on.
  bool get hasFallback => _cache.last != null;
}
