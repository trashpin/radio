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

/// Per-location content completeness — the admin checklist (Hero / Gallery /
/// Narration / GPS / Map) and a completion percentage.
class LocationCompletion {
  const LocationCompletion({
    required this.hero,
    required this.gallery,
    required this.narration,
    required this.gps,
    required this.map,
  });

  final bool hero; // has at least one image
  final bool gallery; // has gallery images beyond the hero
  final bool narration; // has narration/audio
  final bool gps; // has coordinates
  final bool map; // visible on the map (active + not hidden)

  int get present =>
      [hero, gallery, narration, gps, map].where((b) => b).length;
  int get percent => (present / 5 * 100).round();
  bool get complete => present == 5;
}

LocationCompletion completionFor(MasterLocation l) => LocationCompletion(
      hero: l.images.isNotEmpty,
      gallery: l.images.length >= 2,
      narration: l.hasNarration,
      gps: l.hasCoordinates,
      map: l.active && !l.hidden,
    );

/// Image-library health across all locations.
class ImageHealth {
  const ImageHealth({
    required this.totalImages,
    required this.withHero,
    required this.missingHero,
    required this.missingGallery,
    required this.brokenImageLinks,
    required this.duplicateImages,
    required this.locationsComplete,
    required this.locations,
  });

  final int totalImages;
  final int withHero; // visible locations that have a hero
  final int missingHero; // visible locations with no image ("unassigned")
  final int missingGallery;
  final int brokenImageLinks;
  final int duplicateImages;
  final int locationsComplete; // 100% checklist
  final int locations;

  static const empty = ImageHealth(
    totalImages: 0, withHero: 0, missingHero: 0, missingGallery: 0,
    brokenImageLinks: 0, duplicateImages: 0, locationsComplete: 0, locations: 0,
  );
}

ImageHealth computeImageHealth(List<MasterLocation> all) {
  var total = 0, withHero = 0, missingHero = 0, missingGallery = 0;
  var broken = 0, complete = 0;
  final seen = <String>{};
  final dupes = <String>{};
  for (final l in all) {
    total += l.images.length;
    for (final u in l.images) {
      final key = u.trim();
      if (key.isEmpty) continue;
      if (!seen.add(key)) dupes.add(key);
      if (isBrokenAudioLink(u)) broken++;
    }
    final visible = l.active && !l.hidden;
    if (visible && l.images.isEmpty) missingHero++;
    if (visible && l.images.isNotEmpty) withHero++;
    if (visible && l.images.length < 2) missingGallery++;
    if (completionFor(l).complete) complete++;
  }
  return ImageHealth(
    totalImages: total,
    withHero: withHero,
    missingHero: missingHero,
    missingGallery: missingGallery,
    brokenImageLinks: broken,
    duplicateImages: dupes.length,
    locationsComplete: complete,
    locations: all.length,
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
