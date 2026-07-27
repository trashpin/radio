import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';

/// The three AI Narration automation switches (all default OFF).
class NarrationSettings {
  const NarrationSettings({
    this.autoGenerateScripts = false,
    this.autoGenerateAudio = false,
    this.autoPublish = false,
  });

  final bool autoGenerateScripts;
  final bool autoGenerateAudio;
  final bool autoPublish;

  factory NarrationSettings.fromJson(Map<String, dynamic> j) => NarrationSettings(
        autoGenerateScripts: (j['auto_generate_scripts'] ?? false) as bool,
        autoGenerateAudio: (j['auto_generate_audio'] ?? false) as bool,
        autoPublish: (j['auto_publish'] ?? false) as bool,
      );
}

class NarrationSettingsRepository {
  const NarrationSettingsRepository();

  Future<NarrationSettings> load() async {
    if (!SupabaseService.isConfigured) return const NarrationSettings();
    try {
      final rows = await SupabaseService.client
          .from('narration_settings')
          .select()
          .limit(1) as List;
      if (rows.isEmpty) return const NarrationSettings();
      return NarrationSettings.fromJson(rows.first as Map<String, dynamic>);
    } catch (_) {
      // Table not created yet (migration 0023) — safe default is all-OFF.
      return const NarrationSettings();
    }
  }

  /// Update one switch. Column is a whitelisted key.
  Future<void> setFlag(String column, bool value) =>
      SupabaseService.client
          .from('narration_settings')
          .update({column: value}).eq('id', true);
}

final narrationSettingsRepositoryProvider =
    Provider<NarrationSettingsRepository>((ref) => const NarrationSettingsRepository());

class NarrationSettingsRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final narrationSettingsRefreshProvider =
    NotifierProvider<NarrationSettingsRefresh, int>(NarrationSettingsRefresh.new);

final narrationSettingsProvider = FutureProvider<NarrationSettings>((ref) {
  ref.watch(narrationSettingsRefreshProvider);
  return ref.watch(narrationSettingsRepositoryProvider).load();
});
