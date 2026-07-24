import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reports whether the device currently has network connectivity.
///
/// WHY THIS EXISTS: repositories need to decide when to hit Supabase vs. serve
/// cached data. Rather than scatter `try/catch`-and-hope logic everywhere, they
/// ask this service. It's an abstraction so we can plug in a real implementation
/// (e.g. the `connectivity_plus` package) later without changing callers.
///
/// The default [AlwaysOnlineConnectivityService] assumes connectivity, so
/// behavior is unchanged until a real detector is wired in — repositories still
/// fall back to cache automatically if a request fails.
abstract class ConnectivityService {
  Future<bool> get isOnline;
}

/// Default implementation used until a real connectivity plugin is added.
class AlwaysOnlineConnectivityService implements ConnectivityService {
  const AlwaysOnlineConnectivityService();

  @override
  Future<bool> get isOnline async => true;
}

/// Exposes the app-wide [ConnectivityService]. Override in `main`/tests to
/// simulate offline behavior.
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return const AlwaysOnlineConnectivityService();
});
