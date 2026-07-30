import 'package:explorer_os_mobile/features/admin/media_search/logic/search_query.dart';
import 'package:explorer_os_mobile/features/admin/media_search/models/image_search_result.dart';

/// Pure image quality-gate + ranking for the Media Search Center.
///
/// The gate rejects images the brief says are unusable (too small, logos, maps,
/// icons, drawings, non-photos). Ranking scores the survivors so the highest
/// quality, most relevant, best-licensed images sort first ("AI Image Ranking").

/// Minimum acceptable width (px) — the brief's hard floor.
const int kMinImageWidth = 1200;

/// Title/description keywords that mark an image as NOT a usable destination
/// photo (logos, maps, icons, diagrams, flags, seals, documents).
const List<String> _rejectKeywords = [
  'logo', 'icon', 'map ', ' map', 'diagram', 'drawing', 'illustration',
  'sketch', 'clipart', 'clip art', 'flag', 'seal', 'coat of arms', 'chart',
  'graph', 'sign ', 'signage', 'schematic', 'blueprint', 'infographic',
  'screenshot', 'qr code', 'barcode', 'plaque text', '.pdf', '.svg',
];

/// File extensions/mime types we never import as a hero/gallery photo.
const List<String> _rejectMime = ['svg', 'pdf', 'gif', 'tiff'];

bool _looksLikeReject(String text) {
  final t = ' ${text.toLowerCase()} ';
  return _rejectKeywords.any(t.contains);
}

/// The reason an image failed the quality gate (null = it passed).
String? qualityGateFailure(
  ImageSearchResult r, {
  int minWidth = kMinImageWidth,
  bool requirePhoto = true,
}) {
  // Corrupted / unusable formats.
  final mime = (r.mimeType ?? '').toLowerCase();
  final url = r.imageUrl.toLowerCase();
  for (final bad in _rejectMime) {
    if (mime.contains(bad) || url.endsWith('.$bad')) {
      return '$bad files are not imported as photos';
    }
  }
  // Resolution floor (only enforced when the provider reports dimensions).
  if (r.width != null && r.width! < minWidth) {
    return 'Too small (${r.width}px < ${minWidth}px wide)';
  }
  // Logos/maps/icons/drawings by title/description.
  if (requirePhoto &&
      (_looksLikeReject(r.title) ||
          _looksLikeReject(r.description ?? ''))) {
    return 'Looks like a logo/map/diagram, not a photo';
  }
  return null;
}

/// Convenience boolean form of [qualityGateFailure].
bool passesQualityGate(
  ImageSearchResult r, {
  int minWidth = kMinImageWidth,
  bool requirePhoto = true,
}) =>
    qualityGateFailure(r, minWidth: minWidth, requirePhoto: requirePhoto) ==
    null;

/// A 0–100 quality score for a license (more permissive = higher).
int licenseQuality(String? license) {
  final l = (license ?? '').toLowerCase();
  if (l.isEmpty) return 20;
  if (l.contains('pdm') ||
      l.contains('public domain') ||
      l.contains('cc0') ||
      l == 'no known copyright') {
    return 100;
  }
  if (l.contains('by-sa')) return 85;
  if (l.contains('by-nc')) return 55; // non-commercial: usable but weaker
  if (l.contains('by')) return 90;
  if (l.contains('sampling')) return 40;
  return 50;
}

/// The composite ranking score (higher = show first). Weighs:
///   • relevance   — how many destination name tokens the title contains
///   • resolution  — larger images score higher (capped)
///   • orientation — landscape strongly preferred for hero images
///   • license     — more permissive licenses preferred
///   • attribution — a known photographer is a small positive signal
double rankImage(ImageSearchResult r, {required Set<String> nameTokens}) {
  double score = 0;

  // Relevance (0–40): fraction of destination tokens present in the title.
  if (nameTokens.isNotEmpty) {
    final title = r.title.toLowerCase();
    final hits = nameTokens.where(title.contains).length;
    score += 40 * (hits / nameTokens.length);
  } else {
    score += 15;
  }

  // Resolution (0–30): scaled by width up to ~4000px.
  final w = (r.width ?? 0).toDouble();
  score += 30 * (w.clamp(0, 4000) / 4000);

  // Orientation (0–18): landscape best for a hero, square ok, portrait less so.
  score += switch (r.orientation) {
    ImageOrientation.landscape => 18.0,
    ImageOrientation.square => 10.0,
    ImageOrientation.portrait => 4.0,
    ImageOrientation.unknown => 6.0,
  };

  // License (0–8).
  score += 8 * (licenseQuality(r.license) / 100);

  // Attribution present (0–4).
  if ((r.photographer ?? '').trim().isNotEmpty) score += 4;

  return score;
}

/// Applies the quality gate then sorts survivors by descending rank.
List<ImageSearchResult> rankAndFilter(
  List<ImageSearchResult> results, {
  required String destinationName,
  int minWidth = kMinImageWidth,
  bool requirePhoto = true,
}) {
  final tokens = significantTokens(destinationName);
  final kept = results
      .where((r) => passesQualityGate(r,
          minWidth: minWidth, requirePhoto: requirePhoto))
      .toList();
  kept.sort((a, b) =>
      rankImage(b, nameTokens: tokens).compareTo(rankImage(a, nameTokens: tokens)));
  return kept;
}
