/// The catalog a piece of audio lives in. The Audio Recall System unifies all
/// of these into one searchable inventory so ExplorerOS never loses track of a
/// file (Phase 6: merge, never duplicate/delete).
enum AudioSource {
  audioAssets('Audio Studio'),
  songs('Music'),
  narration('Destination Narration'),
  story('Story'),
  djBanter('DJ Banter'),
  radioSegment('Radio Segment'),
  media('Media (Base44)');

  const AudioSource(this.label);
  final String label;
}

typedef Json = Map<String, dynamic>;

/// One normalized entry in the unified audio inventory.
class AudioInventoryItem {
  const AudioInventoryItem({
    required this.source,
    required this.id,
    this.title,
    this.category,
    this.destinationCode,
    this.voice,
    this.language,
    this.durationSeconds,
    this.storagePath,
    this.publicUrl,
    this.status,
    this.playCount = 0,
    this.tags = const [],
  });

  final AudioSource source;
  final String id;
  final String? title;
  final String? category;
  final String? destinationCode;
  final String? voice;
  final String? language;
  final double? durationSeconds;
  final String? storagePath;
  final String? publicUrl;
  final String? status;
  final int playCount;
  final List<String> tags;

  bool get hasFile => (publicUrl ?? '').trim().isNotEmpty;

  String get displayTitle =>
      (title ?? '').trim().isNotEmpty ? title!.trim() : (category ?? id);

  // --- Per-source mappers (defensive: unknown columns → null) --------------

  static double? _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');
  static List<String> _tags(dynamic v) =>
      v is List ? v.map((e) => e.toString()).toList() : const [];

  static AudioInventoryItem fromAudioAsset(Json j) => AudioInventoryItem(
        source: AudioSource.audioAssets,
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? j['voice_name']) as String?,
        category: (j['category'] ?? j['record_type']) as String?,
        destinationCode: j['destination_code'] as String?,
        voice: (j['voice_name'] ?? j['voice']) as String?,
        language: j['language'] as String?,
        durationSeconds: _d(j['duration']),
        storagePath: j['storage_path'] as String?,
        publicUrl: j['public_url'] as String?,
        status: j['status'] as String?,
        playCount: (j['play_count'] as num?)?.toInt() ?? 0,
        tags: _tags(j['tags']),
      );

  static AudioInventoryItem fromSong(Json j) => AudioInventoryItem(
        source: AudioSource.songs,
        id: (j['id'] ?? '').toString(),
        title: j['title'] as String?,
        category: 'music',
        destinationCode: j['park_code'] as String?,
        voice: j['artist'] as String?,
        publicUrl: j['audio_url'] as String?,
        status: (j['is_active'] == true) ? 'active' : 'inactive',
        tags: [
          if (j['genre'] != null) j['genre'].toString(),
          if (j['station'] != null) j['station'].toString(),
        ],
      );

  static AudioInventoryItem fromDestinationNarration(Json j) =>
      AudioInventoryItem(
        source: AudioSource.narration,
        id: (j['id'] ?? '').toString(),
        title: (j['script_type'] ?? 'narration') as String?,
        category: j['script_type'] as String?,
        destinationCode: j['destination_id']?.toString(),
        voice: (j['voice'] ?? j['voice_id']) as String?,
        durationSeconds: _d(j['duration_seconds']),
        publicUrl: j['audio_url'] as String?,
        status: j['status'] as String?,
      );

  static AudioInventoryItem fromStory(Json j) => AudioInventoryItem(
        source: AudioSource.story,
        id: (j['id'] ?? '').toString(),
        title: j['title'] as String?,
        category: (j['category'] ?? 'story') as String?,
        destinationCode: j['park_id']?.toString(),
        voice: j['voice'] as String?,
        durationSeconds: _d(j['duration']),
        publicUrl: j['audio_url'] as String?,
        status: (j['published'] == true) ? 'published' : 'draft',
      );

  static AudioInventoryItem fromDjBanter(Json j) => AudioInventoryItem(
        source: AudioSource.djBanter,
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? j['text'] ?? j['category'] ?? 'DJ banter')
            as String?,
        category: (j['category'] ?? 'dj_banter') as String?,
        voice: (j['voice'] ?? j['voice_id']) as String?,
        publicUrl: (j['audio_url'] ?? j['public_url']) as String?,
        status: j['status'] as String?,
      );

  static AudioInventoryItem fromRadioSegment(Json j) => AudioInventoryItem(
        source: AudioSource.radioSegment,
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? j['name'] ?? j['segment_type']) as String?,
        category: (j['segment_type'] ?? j['type'] ?? 'segment') as String?,
        voice: (j['voice'] ?? j['voice_id']) as String?,
        publicUrl: (j['audio_url'] ?? j['public_url']) as String?,
        status: j['status'] as String?,
      );

  static AudioInventoryItem fromMedia(Json j) => AudioInventoryItem(
        source: AudioSource.media,
        id: (j['id'] ?? j['media_id'] ?? '').toString(),
        title: j['title'] as String?,
        category: (j['media_type'] ?? 'audio') as String?,
        publicUrl: (j['file_url'] ?? j['public_url']) as String?,
      );
}

// --- Pure inventory logic (search / stats / duplicates) --------------------

bool _has(String? s) => s != null && s.trim().isNotEmpty;

/// URLs referenced by more than one inventory item (across all sources).
Set<String> duplicateInventoryUrls(List<AudioInventoryItem> items) {
  final counts = <String, int>{};
  for (final i in items) {
    final u = i.publicUrl;
    if (_has(u)) counts[u!] = (counts[u] ?? 0) + 1;
  }
  return counts.entries.where((e) => e.value > 1).map((e) => e.key).toSet();
}

bool isDuplicate(AudioInventoryItem i, Set<String> dupes) =>
    _has(i.publicUrl) && dupes.contains(i.publicUrl);

/// Filters the inventory by free-text query, source, and file presence.
List<AudioInventoryItem> searchInventory(
  List<AudioInventoryItem> items, {
  String query = '',
  AudioSource? source,
  bool withFileOnly = false,
}) {
  final q = query.trim().toLowerCase();
  return items.where((i) {
    if (source != null && i.source != source) return false;
    if (withFileOnly && !i.hasFile) return false;
    if (q.isEmpty) return true;
    return [
      i.displayTitle,
      i.category ?? '',
      i.voice ?? '',
      i.destinationCode ?? '',
      ...i.tags,
    ].any((f) => f.toLowerCase().contains(q));
  }).toList();
}

class AudioInventoryStats {
  const AudioInventoryStats({
    required this.total,
    required this.withFile,
    required this.orphanScripts,
    required this.duplicates,
    required this.bySource,
    required this.totalPlays,
  });

  final int total;
  final int withFile;

  /// Rows that have no audio file yet (scripts awaiting voicing).
  final int orphanScripts;
  final int duplicates;
  final Map<AudioSource, int> bySource;
  final int totalPlays;

  static const empty = AudioInventoryStats(
    total: 0,
    withFile: 0,
    orphanScripts: 0,
    duplicates: 0,
    bySource: {},
    totalPlays: 0,
  );
}

AudioInventoryStats computeInventoryStats(List<AudioInventoryItem> items) {
  if (items.isEmpty) return AudioInventoryStats.empty;
  final dupes = duplicateInventoryUrls(items);
  final bySource = <AudioSource, int>{};
  var withFile = 0, plays = 0, dupCount = 0;
  for (final i in items) {
    bySource[i.source] = (bySource[i.source] ?? 0) + 1;
    if (i.hasFile) withFile++;
    plays += i.playCount;
    if (isDuplicate(i, dupes)) dupCount++;
  }
  return AudioInventoryStats(
    total: items.length,
    withFile: withFile,
    orphanScripts: items.length - withFile,
    duplicates: dupCount,
    bySource: bySource,
    totalPlays: plays,
  );
}
