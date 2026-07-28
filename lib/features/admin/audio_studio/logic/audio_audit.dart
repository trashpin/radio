import 'package:explorer_os_mobile/features/admin/audio_studio/models/audio_asset.dart';

/// A record that may need narration audio (normalized from any content table).
class AudioRecordRef {
  const AudioRecordRef({
    required this.id,
    required this.category,
    required this.title,
    this.destinationCode,
    this.existingAudioUrl,
  });

  final String id;
  final VoiceCategory category;
  final String title;
  final String? destinationCode;

  /// Audio carried on the record's own row (e.g. `map_locations.audio_url`).
  final String? existingAudioUrl;
}

bool _has(String? s) => s != null && s.trim().isNotEmpty;

bool isBrokenAudioUrl(String? url) {
  if (!_has(url)) return false;
  final u = Uri.tryParse(url!.trim());
  return u == null || !(u.isScheme('http') || u.isScheme('https'));
}

/// URLs used by more than one audio asset (duplicates).
Set<String> duplicateAudioUrls(List<AudioAsset> assets) {
  final counts = <String, int>{};
  for (final a in assets) {
    final url = a.publicUrl ?? a.storagePath;
    if (_has(url)) counts[url!] = (counts[url] ?? 0) + 1;
  }
  return counts.entries.where((e) => e.value > 1).map((e) => e.key).toSet();
}

/// Per-record audio audit result.
class AudioRecordAudit {
  const AudioRecordAudit({
    required this.ref,
    required this.assetCount,
    required this.hasAudio,
    required this.needsRegen,
    required this.broken,
    required this.zeroByte,
    required this.duplicate,
  });

  final AudioRecordRef ref;
  final int assetCount;
  final bool hasAudio;
  final bool needsRegen;
  final bool broken;
  final bool zeroByte;
  final bool duplicate;

  bool get missingAudio => !hasAudio;
  bool get hasIssue =>
      missingAudio || needsRegen || broken || zeroByte || duplicate;
}

/// Aggregate metrics for the Audio Production dashboard.
class AudioDashboardStats {
  const AudioDashboardStats({
    required this.totalRecords,
    required this.recordsWithAudio,
    required this.recordsMissingAudio,
    required this.recordsNeedingRegen,
    required this.brokenFiles,
    required this.zeroByteFiles,
    required this.duplicateFiles,
    required this.storageUsedBytes,
    required this.completionPercent,
    required this.queued,
  });

  final int totalRecords;
  final int recordsWithAudio;
  final int recordsMissingAudio;
  final int recordsNeedingRegen;
  final int brokenFiles;
  final int zeroByteFiles;
  final int duplicateFiles;
  final int storageUsedBytes;
  final double completionPercent;
  final int queued;

  /// Rough remaining generation time, assuming [secondsPerRecord] per file.
  Duration estimatedRemaining({int secondsPerRecord = 8}) =>
      Duration(seconds: recordsMissingAudio * secondsPerRecord);

  static const empty = AudioDashboardStats(
    totalRecords: 0,
    recordsWithAudio: 0,
    recordsMissingAudio: 0,
    recordsNeedingRegen: 0,
    brokenFiles: 0,
    zeroByteFiles: 0,
    duplicateFiles: 0,
    storageUsedBytes: 0,
    completionPercent: 0,
    queued: 0,
  );
}

List<AudioRecordAudit> auditAudio(
  List<AudioRecordRef> records,
  List<AudioAsset> assets,
) {
  final byRecord = <String, List<AudioAsset>>{};
  for (final a in assets) {
    if (a.recordType == null || a.recordId == null) continue;
    byRecord.putIfAbsent('${a.recordType}|${a.recordId}', () => []).add(a);
  }
  final dupes = duplicateAudioUrls(assets);

  return [
    for (final r in records)
      _auditOne(r, byRecord['${r.category.id}|${r.id}'] ?? const [], dupes),
  ];
}

AudioRecordAudit _auditOne(
  AudioRecordRef r,
  List<AudioAsset> assets,
  Set<String> dupes,
) {
  final complete = assets.where((a) => a.status == AudioStatus.complete);
  final hasAudio = _has(r.existingAudioUrl) ||
      complete.any((a) => a.hasFile);
  final needsRegen = assets.any((a) => a.isOutdated && a.hasFile);
  final broken = isBrokenAudioUrl(r.existingAudioUrl) ||
      assets.any((a) => isBrokenAudioUrl(a.publicUrl));
  final zeroByte = assets.any((a) => a.isZeroByte);
  final duplicate = assets.any((a) {
    final url = a.publicUrl ?? a.storagePath;
    return url != null && dupes.contains(url);
  });

  return AudioRecordAudit(
    ref: r,
    assetCount: assets.length,
    hasAudio: hasAudio,
    needsRegen: needsRegen,
    broken: broken,
    zeroByte: zeroByte,
    duplicate: duplicate,
  );
}

AudioDashboardStats computeAudioDashboard(
  List<AudioRecordRef> records,
  List<AudioAsset> assets, {
  int queued = 0,
}) {
  if (records.isEmpty && assets.isEmpty) {
    return AudioDashboardStats.empty.copyWithQueued(queued);
  }
  final audits = auditAudio(records, assets);
  final dupes = duplicateAudioUrls(assets);

  var withAudio = 0, missing = 0, regen = 0;
  for (final a in audits) {
    if (a.hasAudio) withAudio++;
    if (a.missingAudio) missing++;
    if (a.needsRegen) regen++;
  }

  return AudioDashboardStats(
    totalRecords: records.length,
    recordsWithAudio: withAudio,
    recordsMissingAudio: missing,
    recordsNeedingRegen: regen,
    brokenFiles: assets.where((a) => isBrokenAudioUrl(a.publicUrl)).length,
    zeroByteFiles: assets.where((a) => a.isZeroByte).length,
    duplicateFiles: assets.where((a) {
      final url = a.publicUrl ?? a.storagePath;
      return url != null && dupes.contains(url);
    }).length,
    storageUsedBytes:
        assets.fold(0, (sum, a) => sum + (a.fileSize ?? 0)),
    completionPercent:
        records.isEmpty ? 0 : (withAudio / records.length) * 100,
    queued: queued,
  );
}

/// CSV report of the audio audit (one row per record).
String audioCsv(List<AudioRecordAudit> audits) {
  String esc(String? v) => '"${(v ?? '').replaceAll('"', '""')}"';
  String yn(bool b) => b ? 'YES' : '';
  final rows = <String>[
    [
      'record_id',
      'category',
      'title',
      'destination_code',
      'asset_count',
      'has_audio',
      'missing_audio',
      'needs_regen',
      'broken',
      'zero_byte',
      'duplicate',
    ].join(','),
  ];
  for (final a in audits) {
    rows.add([
      esc(a.ref.id),
      esc(a.ref.category.id),
      esc(a.ref.title),
      esc(a.ref.destinationCode),
      '${a.assetCount}',
      yn(a.hasAudio),
      yn(a.missingAudio),
      yn(a.needsRegen),
      yn(a.broken),
      yn(a.zeroByte),
      yn(a.duplicate),
    ].join(','));
  }
  return rows.join('\n');
}

extension on AudioDashboardStats {
  AudioDashboardStats copyWithQueued(int q) => AudioDashboardStats(
        totalRecords: totalRecords,
        recordsWithAudio: recordsWithAudio,
        recordsMissingAudio: recordsMissingAudio,
        recordsNeedingRegen: recordsNeedingRegen,
        brokenFiles: brokenFiles,
        zeroByteFiles: zeroByteFiles,
        duplicateFiles: duplicateFiles,
        storageUsedBytes: storageUsedBytes,
        completionPercent: completionPercent,
        queued: q,
      );
}

/// Human-readable byte size (e.g. "12.4 MB").
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}
