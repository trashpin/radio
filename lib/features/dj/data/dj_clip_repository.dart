import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/dj/models/dj_clip.dart';

/// Reads pre-generated DJ banter clips from `dj_banter_clips`. Returns an empty
/// list if the table doesn't exist yet or Supabase isn't configured, so the
/// runtime simply falls back to TTS.
class DjClipRepository {
  const DjClipRepository();

  Future<List<DjClip>> all() async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client.from('dj_banter_clips').select()
          as List;
      return rows
          .cast<Map<String, dynamic>>()
          .map(DjClip.fromJson)
          .whereType<DjClip>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}

final djClipRepositoryProvider =
    Provider<DjClipRepository>((ref) => const DjClipRepository());

/// All pre-generated DJ clips (empty until generated via `tool/dj_audio.dart`).
final djClipsProvider =
    FutureProvider<List<DjClip>>((ref) => ref.watch(djClipRepositoryProvider).all());
