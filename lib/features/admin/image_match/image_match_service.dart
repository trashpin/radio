import 'dart:typed_data';

import 'package:explorer_os_mobile/features/admin/image_match/filename_normalizer.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';

/// A picked image awaiting matching.
class ImageCandidate {
  ImageCandidate({required this.filename, this.bytes})
      : matchKey = matchKeyFromFilename(filename),
        extension = _ext(filename);

  final String filename;
  final String matchKey;
  final String extension;
  final Uint8List? bytes;

  static String _ext(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(dot + 1).toLowerCase() : 'jpg';
  }
}

enum MatchStatus { matched, multiMatch, unmatched, skipped, uploaded, failed }

/// One row of the import report.
class MatchRow {
  MatchRow(this.candidate, this.status, {this.species, this.matches = const [], this.note});
  final ImageCandidate candidate;
  MatchStatus status;
  Species? species; // resolved single match
  List<Species> matches; // for multiMatch (selection dialog)
  String? note;
}

/// Aggregate import report with the requested counters.
class ImportReport {
  ImportReport(this.rows);
  final List<MatchRow> rows;

  int get total => rows.length;
  int get matched =>
      rows.where((r) => r.status == MatchStatus.matched || r.status == MatchStatus.uploaded).length;
  int get uploaded => rows.where((r) => r.status == MatchStatus.uploaded).length;
  int get updated => uploaded; // one update per uploaded image
  int get skipped => rows.where((r) => r.status == MatchStatus.skipped).length;
  int get unmatched => rows.where((r) => r.status == MatchStatus.unmatched).length;
  int get multiMatch => rows.where((r) => r.status == MatchStatus.multiMatch).length;

  List<MatchRow> get unmatchedRows =>
      rows.where((r) => r.status == MatchStatus.unmatched).toList();
  List<MatchRow> get multiMatchRows =>
      rows.where((r) => r.status == MatchStatus.multiMatch).toList();

  String toReportText() {
    final b = StringBuffer('ExplorerOS Image Import Report\n')
      ..writeln('Total: $total  Matched: $matched  Uploaded: $uploaded  '
          'Updated: $updated  Skipped: $skipped  Unmatched: $unmatched\n');
    for (final r in rows) {
      b.writeln('${r.candidate.filename}  →  ${r.status.name}'
          '${r.species != null ? '  (${r.species!.commonName})' : ''}'
          '${r.note != null ? '  — ${r.note}' : ''}');
    }
    return b.toString();
  }
}

/// Matches uploaded images to species by normalized filename (`match_key`),
/// classifying each into matched / multiMatch / unmatched / skipped.
class ImageMatchService {
  const ImageMatchService();

  /// Index species by their match_key (normalized common name).
  Map<String, List<Species>> indexByMatchKey(List<Species> species) {
    final map = <String, List<Species>>{};
    for (final s in species) {
      final key = normalizeMatchKey(s.commonName);
      map.putIfAbsent(key, () => []).add(s);
    }
    return map;
  }

  ImportReport classify(
    List<ImageCandidate> candidates,
    List<Species> species, {
    bool replaceExisting = false,
  }) {
    final index = indexByMatchKey(species);
    final rows = <MatchRow>[];
    for (final c in candidates) {
      final matches = index[c.matchKey] ?? const [];
      if (matches.isEmpty) {
        rows.add(MatchRow(c, MatchStatus.unmatched));
      } else if (matches.length > 1) {
        rows.add(MatchRow(c, MatchStatus.multiMatch, matches: [...matches]));
      } else {
        final s = matches.first;
        final hasImage = (s.heroImage?.isNotEmpty ?? false);
        if (hasImage && !replaceExisting) {
          rows.add(MatchRow(c, MatchStatus.skipped,
              species: s, note: 'existing image kept'));
        } else {
          rows.add(MatchRow(c, MatchStatus.matched, species: s));
        }
      }
    }
    return ImportReport(rows);
  }

  /// Storage path organized by park/category (e.g. ocala/plants/saw_palmetto.jpg).
  String storagePath(String? parkCode, String category, ImageCandidate c) {
    final park = normalizeMatchKey(parkCode ?? 'unknown_park');
    final cat = normalizeMatchKey(category.isEmpty ? 'uncategorized' : category);
    return '$park/$cat/${c.matchKey}.${c.extension}';
  }

  /// Supabase image-transform thumbnail URL (optimized, ~240px wide).
  String thumbnailUrlFor(String publicUrl) {
    final render = publicUrl.replaceFirst(
        '/storage/v1/object/public/', '/storage/v1/render/image/public/');
    return '$render?width=240&quality=70';
  }
}
