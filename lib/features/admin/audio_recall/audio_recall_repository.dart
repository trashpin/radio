import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/admin/audio_recall/audio_recall.dart';

/// Assembles the unified audio inventory by reading every catalog and
/// normalizing to [AudioInventoryItem]. Read-only across the other catalogs —
/// it never modifies them (Phase 6). `audio_assets` is the canonical index for
/// play tracking.
class AudioRecallRepository {
  const AudioRecallRepository();

  Future<List<Map<String, dynamic>>> _rows(String table,
      {String select = '*'}) async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client.from(table).select(select)
          as List;
      return rows.cast<Map<String, dynamic>>();
    } catch (_) {
      return const [];
    }
  }

  Future<List<AudioInventoryItem>> inventory() async {
    final out = <AudioInventoryItem>[];
    for (final r in await _rows('audio_assets')) {
      out.add(AudioInventoryItem.fromAudioAsset(r));
    }
    for (final r in await _rows('songs')) {
      out.add(AudioInventoryItem.fromSong(r));
    }
    for (final r in await _rows('destination_narrations')) {
      out.add(AudioInventoryItem.fromDestinationNarration(r));
    }
    for (final r in await _rows('story_library')) {
      out.add(AudioInventoryItem.fromStory(r));
    }
    for (final r in await _rows('dj_banter_clips')) {
      out.add(AudioInventoryItem.fromDjBanter(r));
    }
    for (final r in await _rows('radio_segments')) {
      out.add(AudioInventoryItem.fromRadioSegment(r));
    }
    for (final r
        in await _rows('media', select: 'id,title,media_type,file_url')) {
      if ((r['media_type'] ?? '').toString().toLowerCase() == 'audio') {
        out.add(AudioInventoryItem.fromMedia(r));
      }
    }
    return out;
  }

  /// Records a play against the canonical `audio_assets` index.
  Future<void> recordPlay(String audioAssetId, {String? usedBy}) async {
    if (!SupabaseService.isConfigured) return;
    try {
      await SupabaseService.client.rpc('audio_asset_record_play', params: {
        'p_id': audioAssetId,
        'p_used_by': usedBy,
      });
    } catch (_) {
      // Function may not exist until 0027 is applied — ignore.
    }
  }
}

final audioRecallRepositoryProvider =
    Provider<AudioRecallRepository>((ref) => const AudioRecallRepository());

final audioRecallRefreshProvider =
    NotifierProvider<AudioRecallRefresh, int>(AudioRecallRefresh.new);

class AudioRecallRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final audioInventoryProvider =
    FutureProvider<List<AudioInventoryItem>>((ref) {
  ref.watch(audioRecallRefreshProvider);
  return ref.watch(audioRecallRepositoryProvider).inventory();
});

final audioInventoryStatsProvider = Provider<AudioInventoryStats>((ref) {
  final items = ref.watch(audioInventoryProvider).value ?? const [];
  return computeInventoryStats(items);
});
