import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/narration/models/voice.dart';

/// Loads the ElevenLabs voice catalog.
///
/// Today the catalog is a bundled asset (generated server-side, since the
/// browser can't call ElevenLabs and the current key lacks `voices_read`).
/// The [refresh] seam re-reads it; a future `voices_read` key + server sync can
/// populate this from Supabase without changing the UI.
class VoiceRepository {
  const VoiceRepository();
  static const _asset = 'assets/data/elevenlabs_voices.json';

  Future<List<Voice>> loadVoices() async {
    final raw = await rootBundle.loadString(_asset);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = (json['voices'] as List).cast<Map<String, dynamic>>();
    return list.map(Voice.fromJson).toList(growable: false);
  }
}

final voiceRepositoryProvider =
    Provider<VoiceRepository>((ref) => const VoiceRepository());

/// Available ElevenLabs voices (refreshable).
final voicesProvider = FutureProvider<List<Voice>>((ref) async {
  ref.watch(voicesRefreshProvider);
  return ref.watch(voiceRepositoryProvider).loadVoices();
});

/// Bump to force [voicesProvider] to reload (Refresh button).
class VoicesRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final voicesRefreshProvider =
    NotifierProvider<VoicesRefresh, int>(VoicesRefresh.new);

void refreshVoices(WidgetRef ref) =>
    ref.read(voicesRefreshProvider.notifier).bump();

/// The globally selected voice used by "Generate Audio" when a category has no
/// specific assignment. Defaults to the first voice.
class SelectedVoice extends Notifier<Voice?> {
  @override
  Voice? build() {
    final voices = ref.watch(voicesProvider).value ?? const [];
    return voices.isEmpty ? null : voices.first;
  }

  void select(Voice v) => state = v;
}

final selectedVoiceProvider =
    NotifierProvider<SelectedVoice, Voice?>(SelectedVoice.new);

/// Default voice per content category (category token -> voice_id).
class CategoryVoices extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() {
    // Seed from each voice's suggested_category.
    final voices = ref.watch(voicesProvider).value ?? const [];
    return {
      for (final v in voices)
        if (v.suggestedCategory != null) v.suggestedCategory!: v.voiceId,
    };
  }

  void assign(String category, String voiceId) =>
      state = {...state, category: voiceId};
}

final categoryVoicesProvider =
    NotifierProvider<CategoryVoices, Map<String, String>>(CategoryVoices.new);

/// The voice to use for a given category: the category default, else the
/// globally selected voice.
Voice? voiceForCategory(WidgetRef ref, String category) {
  final voices = ref.read(voicesProvider).value ?? const [];
  if (voices.isEmpty) return null;
  final map = ref.read(categoryVoicesProvider);
  final id = map[category];
  if (id != null) {
    return voices.firstWhere((v) => v.voiceId == id,
        orElse: () => ref.read(selectedVoiceProvider) ?? voices.first);
  }
  return ref.read(selectedVoiceProvider) ?? voices.first;
}
