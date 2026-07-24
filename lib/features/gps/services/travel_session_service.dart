import 'package:explorer_os_mobile/features/gps/models/travel_session.dart';
import 'package:explorer_os_mobile/features/gps/models/travel_statistics.dart';

/// Owns the current [TravelSession]: starting, ending, resetting, and folding
/// per-fix updates into cumulative session statistics.
///
/// WHY THIS EXISTS: a "trip" is a first-class concept (trip summaries, history,
/// resuming). Extracting session/stats bookkeeping from the GPSService keeps the
/// engine focused on per-fix reasoning and makes sessions independently
/// testable and persistable (via TravelRepository).
class TravelSessionService {
  TravelSession? _current;
  int _seq = 0;

  TravelSession? get current => _current;

  /// Starts a fresh session (ending any active one first).
  TravelSession start({DateTime? at}) {
    final now = at ?? DateTime.now();
    _current = TravelSession(
      id: 'session_${_seq++}_${now.millisecondsSinceEpoch}',
      startedAt: now,
      statistics: TravelStatistics(tripStartedAt: now),
    );
    return _current!;
  }

  /// Ends the active session (marking it inactive with an end time).
  TravelSession? stop({DateTime? at}) {
    final session = _current;
    if (session == null) return null;
    _current = session.copyWith(active: false, endedAt: at ?? DateTime.now());
    return _current;
  }

  /// Ends the current session and starts a brand new one.
  TravelSession reset() {
    stop();
    return start();
  }

  /// Folds a fix's derived statistics into the active session.
  void recordFix(TravelStatistics statistics) {
    final session = _current;
    if (session == null) return;
    _current = session.copyWith(
      fixCount: session.fixCount + 1,
      statistics: statistics,
    );
  }
}
