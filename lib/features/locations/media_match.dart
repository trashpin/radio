import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

/// Result of matching an uploaded file to a master location.
class MediaMatch {
  const MediaMatch({required this.filename, this.location, this.isHero = false});
  final String filename;
  final MasterLocation? location; // null → Unassigned
  final bool isHero; // filename hints a hero image
  bool get matched => location != null;
}

/// Normalizes a filename (or name) to comparable tokens: lowercase, strip the
/// extension + common role/size suffixes, collapse separators to single spaces.
String normalizeMediaName(String raw) {
  var s = raw.toLowerCase().trim();
  final slash = s.lastIndexOf('/');
  if (slash >= 0) s = s.substring(slash + 1);
  final dot = s.lastIndexOf('.');
  if (dot > 0) s = s.substring(0, dot);
  // Drop role/size hints so "lake_bryant_hero" matches "Lake Bryant".
  s = s.replaceAll(
      RegExp(
          r'(hero|gallery|thumb|thumbnail|drone|wildlife|plant|historic(al)?|photo|image|img|cover|banner|\d+x\d+|\d{2,4}p|\bhd\b|\b4k\b)'),
      ' ');
  s = s.replaceAll(RegExp(r'[_\-.]+'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

bool _isHeroName(String raw) =>
    RegExp(r'hero|cover|banner|main').hasMatch(raw.toLowerCase());

/// Matches [filename] to the best location by normalized-name overlap. Prefers
/// an exact normalized match, then a location whose normalized name is fully
/// contained in the filename tokens. Returns an unmatched result otherwise.
MediaMatch matchMediaToLocation(
    String filename, List<MasterLocation> locations) {
  final target = normalizeMediaName(filename);
  final isHero = _isHeroName(filename);
  if (target.isEmpty) return MediaMatch(filename: filename, isHero: isHero);

  MasterLocation? exact;
  MasterLocation? contains;
  var bestLen = -1;
  for (final l in locations) {
    final name = normalizeMediaName(l.name);
    if (name.isEmpty) continue;
    if (name == target) {
      exact = l;
      break;
    }
    // "lake bryant hero" contains "lake bryant"; prefer the longest such name.
    if (target.contains(name) && name.length > bestLen) {
      contains = l;
      bestLen = name.length;
    }
  }
  final match = exact ?? contains;
  return MediaMatch(filename: filename, location: match, isHero: isHero);
}
