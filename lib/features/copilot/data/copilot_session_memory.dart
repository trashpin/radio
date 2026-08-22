/// Per-trip "already said that" memory — mirrors the existing `BanterTrip`
/// concept already used by GPS DJ banter (in-memory only, cleared on a new
/// trip, never persisted to disk). Spec §10: "remember what it has already
/// said during the current trip/session... do not repeatedly announce the
/// same location... do not repeatedly tell the same historical story."
class CopilotSessionMemory {
  final Set<String> _spokenKeys = {};
  DateTime? _lastSpokenAt;

  bool hasSpoken(String dedupeKey) => _spokenKeys.contains(dedupeKey);

  void markSpoken(String dedupeKey, {DateTime? now}) {
    _spokenKeys.add(dedupeKey);
    _lastSpokenAt = now ?? DateTime.now();
  }

  Duration? get sinceLastSpoken {
    final last = _lastSpokenAt;
    if (last == null) return null;
    return DateTime.now().difference(last);
  }

  /// Called when a new trip starts — resets the anti-repeat set but keeps the
  /// "how long has it been quiet" clock running (a fresh trip shouldn't force
  /// the copilot to speak immediately just because memory was cleared).
  void resetForNewTrip() => _spokenKeys.clear();
}
