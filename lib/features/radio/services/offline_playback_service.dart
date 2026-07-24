import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';

/// Tracks which audio has been downloaded for offline playback.
///
/// WHY THIS EXISTS: offline exploration needs downloaded music/narration. This
/// service is the registry/seam: it answers "is this segment available offline,
/// and where?" so playback can prefer a local file when there's no signal. A
/// real implementation persists the registry and manages files on disk; the
/// engine only asks these questions.
class OfflinePlaybackService {
  final Map<String, String> _localPathBySegmentId = {};

  bool isAvailableOffline(AudioSegment segment) =>
      _localPathBySegmentId.containsKey(segment.id);

  String? localPath(String segmentId) => _localPathBySegmentId[segmentId];

  /// Registers a downloaded file for a segment (called by the future download
  /// manager).
  void markDownloaded(String segmentId, String path) =>
      _localPathBySegmentId[segmentId] = path;

  void remove(String segmentId) => _localPathBySegmentId.remove(segmentId);
  void clear() => _localPathBySegmentId.clear();
}
