import 'package:explorer_os_mobile/features/admin/media_manager/models/media_asset.dart';
import 'package:explorer_os_mobile/features/admin/media_manager/models/media_record.dart';

/// The per-record result of a media audit.
class RecordAudit {
  const RecordAudit({
    required this.record,
    required this.galleryCount,
    required this.videoCount,
    required this.audioCount,
    required this.missingHero,
    required this.missingGallery,
    required this.missingAudio,
    required this.missingVideo,
    required this.missingAltText,
    required this.missingCopyright,
    required this.missingCredits,
    required this.brokenFile,
    required this.duplicateFile,
  });

  final MediaRecord record;
  final int galleryCount;
  final int videoCount;
  final int audioCount;
  final bool missingHero;
  final bool missingGallery;
  final bool missingAudio;
  final bool missingVideo;
  final bool missingAltText;
  final bool missingCopyright;
  final bool missingCredits;
  final bool brokenFile;
  final bool duplicateFile;

  /// Fraction (0..1) of the six core media components present for this record:
  /// hero, gallery(≥1), audio, alt text, copyright, credits.
  double get completion {
    var present = 0;
    if (!missingHero) present++;
    if (!missingGallery) present++;
    if (!missingAudio) present++;
    if (!missingAltText) present++;
    if (!missingCopyright) present++;
    if (!missingCredits) present++;
    return present / 6.0;
  }

  bool get hasIssue =>
      missingHero ||
      missingGallery ||
      missingAudio ||
      missingVideo ||
      missingAltText ||
      missingCopyright ||
      missingCredits ||
      brokenFile ||
      duplicateFile;
}

/// Aggregate metrics for the Media Manager dashboard.
class MediaDashboardStats {
  const MediaDashboardStats({
    required this.totalRecords,
    required this.totalImages,
    required this.totalVideos,
    required this.totalAudio,
    required this.recordsMissingHero,
    required this.recordsMissingGallery,
    required this.recordsMissingAudio,
    required this.brokenImageLinks,
    required this.duplicateImages,
    required this.completionPercent,
  });

  final int totalRecords;
  final int totalImages;
  final int totalVideos;
  final int totalAudio;
  final int recordsMissingHero;
  final int recordsMissingGallery;
  final int recordsMissingAudio;
  final int brokenImageLinks;
  final int duplicateImages;

  /// Overall media completion across all records, 0..100.
  final double completionPercent;

  static const empty = MediaDashboardStats(
    totalRecords: 0,
    totalImages: 0,
    totalVideos: 0,
    totalAudio: 0,
    recordsMissingHero: 0,
    recordsMissingGallery: 0,
    recordsMissingAudio: 0,
    brokenImageLinks: 0,
    duplicateImages: 0,
    completionPercent: 0,
  );
}

bool _has(String? s) => s != null && s.trim().isNotEmpty;

/// A URL is "broken" (from a static perspective) when present but not a
/// well-formed http(s) URL. Live reachability isn't checked client-side.
bool isBrokenUrl(String? url) {
  if (!_has(url)) return false;
  final u = Uri.tryParse(url!.trim());
  return u == null || !(u.isScheme('http') || u.isScheme('https'));
}

/// Set of URLs that appear on more than one asset (duplicate files).
Set<String> duplicateUrls(List<MediaAsset> assets) {
  final counts = <String, int>{};
  for (final a in assets) {
    final url = a.publicUrl ?? a.storagePath;
    if (_has(url)) counts[url!] = (counts[url] ?? 0) + 1;
  }
  return counts.entries
      .where((e) => e.value > 1)
      .map((e) => e.key)
      .toSet();
}

/// Audits every [record], combining fields carried on the record itself with
/// its attached [assets].
List<RecordAudit> auditRecords(
  List<MediaRecord> records,
  List<MediaAsset> assets,
) {
  final byRecord = <String, List<MediaAsset>>{};
  for (final a in assets) {
    if (a.recordType == null || a.recordId == null) continue;
    byRecord.putIfAbsent('${a.recordType}|${a.recordId}', () => []).add(a);
  }
  final dupes = duplicateUrls(assets);

  return [
    for (final r in records) _auditOne(r, byRecord[r.key] ?? const [], dupes),
  ];
}

RecordAudit _auditOne(
  MediaRecord r,
  List<MediaAsset> assets,
  Set<String> dupes,
) {
  final images = assets.where((a) => a.mediaType == MediaType.image).toList();
  final heroAssets = images.where((a) => a.isHero).toList();
  final gallery = images.where((a) => !a.isHero).toList();
  final videos = assets.where((a) => a.mediaType == MediaType.video).toList();
  final audios = assets.where((a) => a.isAudioLike).toList();

  final heroPresent = _has(r.heroImageUrl) || heroAssets.isNotEmpty;
  final galleryPresent = gallery.isNotEmpty;
  final audioPresent = _has(r.audioUrl) || audios.isNotEmpty;
  final videoPresent = videos.isNotEmpty;

  final altPresent =
      _has(r.altText) || images.any((a) => _has(a.altText));
  final copyrightPresent =
      _has(r.copyright) || assets.any((a) => _has(a.copyright));
  final creditsPresent =
      _has(r.credits) || assets.any((a) => _has(a.photographer));

  final broken = isBrokenUrl(r.heroImageUrl) ||
      assets.any((a) => isBrokenUrl(a.publicUrl));
  final duplicate = assets.any((a) {
    final url = a.publicUrl ?? a.storagePath;
    return url != null && dupes.contains(url);
  });

  return RecordAudit(
    record: r,
    galleryCount: gallery.length,
    videoCount: videos.length,
    audioCount: audios.length + (_has(r.audioUrl) ? 1 : 0),
    missingHero: !heroPresent,
    missingGallery: !galleryPresent,
    missingAudio: !audioPresent,
    missingVideo: !videoPresent,
    missingAltText: !altPresent,
    missingCopyright: !copyrightPresent,
    missingCredits: !creditsPresent,
    brokenFile: broken,
    duplicateFile: duplicate,
  );
}

/// Computes the dashboard metrics from all records + assets.
MediaDashboardStats computeDashboard(
  List<MediaRecord> records,
  List<MediaAsset> assets,
) {
  if (records.isEmpty && assets.isEmpty) return MediaDashboardStats.empty;
  final audits = auditRecords(records, assets);
  final dupes = duplicateUrls(assets);

  var missingHero = 0, missingGallery = 0, missingAudio = 0;
  var completionSum = 0.0;
  for (final a in audits) {
    if (a.missingHero) missingHero++;
    if (a.missingGallery) missingGallery++;
    if (a.missingAudio) missingAudio++;
    completionSum += a.completion;
  }

  final totalImages =
      assets.where((a) => a.mediaType == MediaType.image).length;
  final totalVideos =
      assets.where((a) => a.mediaType == MediaType.video).length;
  final totalAudio = assets.where((a) => a.isAudioLike).length;
  final broken = assets.where((a) => isBrokenUrl(a.publicUrl)).length;
  final duplicateImages = assets.where((a) {
    final url = a.publicUrl ?? a.storagePath;
    return url != null && dupes.contains(url);
  }).length;

  return MediaDashboardStats(
    totalRecords: records.length,
    totalImages: totalImages,
    totalVideos: totalVideos,
    totalAudio: totalAudio,
    recordsMissingHero: missingHero,
    recordsMissingGallery: missingGallery,
    recordsMissingAudio: missingAudio,
    brokenImageLinks: broken,
    duplicateImages: duplicateImages,
    completionPercent:
        records.isEmpty ? 0 : (completionSum / records.length) * 100,
  );
}

/// Builds a CSV report of the audit (one row per record).
String auditCsv(List<RecordAudit> audits) {
  String esc(String? v) {
    final s = (v ?? '').replaceAll('"', '""');
    return '"$s"';
  }

  String yn(bool b) => b ? 'YES' : '';

  final rows = <String>[
    [
      'record_id',
      'record_type',
      'title',
      'destination_id',
      'gallery_count',
      'video_count',
      'audio_count',
      'missing_hero',
      'missing_gallery',
      'missing_audio',
      'missing_video',
      'missing_alt_text',
      'missing_copyright',
      'missing_credits',
      'broken_file',
      'duplicate_file',
      'completion_percent',
    ].join(','),
  ];
  for (final a in audits) {
    rows.add([
      esc(a.record.id),
      esc(a.record.type.name),
      esc(a.record.title),
      esc(a.record.destinationId),
      '${a.galleryCount}',
      '${a.videoCount}',
      '${a.audioCount}',
      yn(a.missingHero),
      yn(a.missingGallery),
      yn(a.missingAudio),
      yn(a.missingVideo),
      yn(a.missingAltText),
      yn(a.missingCopyright),
      yn(a.missingCredits),
      yn(a.brokenFile),
      yn(a.duplicateFile),
      (a.completion * 100).round().toString(),
    ].join(','));
  }
  return rows.join('\n');
}
