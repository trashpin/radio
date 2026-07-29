import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

/// True when [url] is non-empty but not a usable http(s) link.
bool isBrokenAudioLink(String? url) {
  final u = (url ?? '').trim();
  if (u.isEmpty) return false; // empty = "missing", not "broken"
  final uri = Uri.tryParse(u);
  if (uri == null || !uri.hasScheme) return true;
  if (uri.scheme != 'http' && uri.scheme != 'https') return true;
  return !uri.hasAuthority;
}

/// Aggregate health of the master location database — what's ready vs. what
/// needs attention.
class LocationHealth {
  const LocationHealth({
    required this.total,
    required this.ready,
    required this.pending,
    required this.disabled,
    required this.missingAudio,
    required this.missingImages,
    required this.missingCoordinates,
    required this.brokenAudio,
    required this.hidden,
    this.lastGenerated,
  });

  final int total;
  final int ready;
  final int pending;
  final int disabled;
  final int missingAudio;
  final int missingImages;
  final int missingCoordinates;
  final int brokenAudio;
  final int hidden;
  final DateTime? lastGenerated;

  /// Fraction of locations that are Ready (0..1).
  double get readyProgress => total == 0 ? 0 : ready / total;

  static const empty = LocationHealth(
    total: 0, ready: 0, pending: 0, disabled: 0, missingAudio: 0,
    missingImages: 0, missingCoordinates: 0, brokenAudio: 0, hidden: 0,
  );
}

LocationHealth computeLocationHealth(List<MasterLocation> all) {
  var ready = 0, pending = 0, disabled = 0;
  var missingAudio = 0, missingImages = 0, missingCoords = 0, broken = 0, hidden = 0;
  DateTime? last;
  for (final l in all) {
    switch (l.status) {
      case LocationStatus.ready:
        ready++;
        if (l.updatedAt != null &&
            (last == null || l.updatedAt!.isAfter(last))) {
          last = l.updatedAt;
        }
      case LocationStatus.pending:
        pending++;
      case LocationStatus.disabled:
        disabled++;
    }
    if (l.status != LocationStatus.disabled && !l.hasAudio) missingAudio++;
    if (l.status != LocationStatus.disabled && l.images.isEmpty) missingImages++;
    if (!l.hasCoordinates) missingCoords++;
    if (!l.active || l.hidden) hidden++;
    for (final u in l.audioFiles) {
      if (isBrokenAudioLink(u)) broken++;
    }
  }
  return LocationHealth(
    total: all.length,
    ready: ready,
    pending: pending,
    disabled: disabled,
    missingAudio: missingAudio,
    missingImages: missingImages,
    missingCoordinates: missingCoords,
    brokenAudio: broken,
    hidden: hidden,
    lastGenerated: last,
  );
}
