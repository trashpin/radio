import 'package:csv/csv.dart';

/// One parsed row from a music CSV import.
class MusicImportRow {
  const MusicImportRow({
    required this.title,
    this.artist,
    this.album,
    this.genre,
    this.mood,
    this.audioUrl,
    this.stationId,
    this.durationSeconds,
  });

  final String title;
  final String? artist;
  final String? album;
  final String? genre;
  final String? mood;
  final String? audioUrl;
  final String? stationId;
  final int? durationSeconds;
}

/// Parses a music-library CSV into structured [MusicImportRow]s.
///
/// Pure and dependency-light (uses the `csv` package) so bulk import is
/// deterministic and unit-testable. Expects a header row; recognized columns:
/// `title, artist, album, genre, mood, audio_url, duration_seconds, station_id`
/// (extra columns are ignored; column order is irrelevant).
class CSVImporter {
  const CSVImporter();

  List<MusicImportRow> parse(String csvContent) {
    final rows = Csv(dynamicTyping: false).decode(csvContent);
    if (rows.isEmpty) return const [];

    final header =
        rows.first.map((c) => c.toString().trim().toLowerCase()).toList();
    int col(String name) => header.indexOf(name);
    final ti = col('title');
    final ar = col('artist');
    final al = col('album');
    final ge = col('genre');
    final mo = col('mood');
    final au = col('audio_url');
    final du = col('duration_seconds');
    final st = col('station_id');

    String? cell(List<dynamic> row, int i) {
      if (i < 0 || i >= row.length) return null;
      final value = row[i].toString().trim();
      return value.isEmpty ? null : value;
    }

    final result = <MusicImportRow>[];
    for (final row in rows.skip(1)) {
      final title = cell(row, ti);
      if (title == null) continue;
      result.add(MusicImportRow(
        title: title,
        artist: cell(row, ar),
        album: cell(row, al),
        genre: cell(row, ge),
        mood: cell(row, mo),
        audioUrl: cell(row, au),
        stationId: cell(row, st),
        durationSeconds: int.tryParse(cell(row, du) ?? ''),
      ));
    }
    return result;
  }
}
