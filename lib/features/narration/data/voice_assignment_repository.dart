import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';

/// A default-voice assignment for one content category.
class VoiceAssignment {
  const VoiceAssignment({
    required this.category,
    this.defaultVoiceName,
    this.defaultVoiceId,
    this.language = 'English',
    this.active = true,
  });

  final String category;
  final String? defaultVoiceName;
  final String? defaultVoiceId;
  final String language;
  final bool active;

  factory VoiceAssignment.fromJson(Map<String, dynamic> j) => VoiceAssignment(
        category: (j['category'] ?? '') as String,
        defaultVoiceName: j['default_voice_name'] as String?,
        defaultVoiceId: j['default_voice_id'] as String?,
        language: (j['language'] ?? 'English') as String,
        active: (j['active'] ?? true) as bool,
      );

  Map<String, dynamic> toJson() => {
        'category': category,
        'default_voice_name': defaultVoiceName,
        'default_voice_id': defaultVoiceId,
        'language': language,
        'active': active,
      };
}

/// Read/write the `voice_assignments` table (category -> default voice).
class VoiceAssignmentRepository {
  const VoiceAssignmentRepository(this._client);
  final dynamic _client; // SupabaseClient

  static const _table = 'voice_assignments';

  Future<Map<String, VoiceAssignment>> loadAll() async {
    final rows = await _client.from(_table).select() as List;
    return {
      for (final r in rows.cast<Map<String, dynamic>>())
        (r['category'] as String): VoiceAssignment.fromJson(r),
    };
  }

  Future<void> assign(String category, String voiceName, String voiceId) async {
    await _client.from(_table).upsert({
      'category': category,
      'default_voice_name': voiceName,
      'default_voice_id': voiceId,
      'language': 'English',
      'active': true,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}

final voiceAssignmentRepositoryProvider =
    Provider<VoiceAssignmentRepository>((ref) {
  return VoiceAssignmentRepository(ref.watch(supabaseClientProvider));
});

/// Loaded assignments (category token -> assignment). Empty if the table isn't
/// present yet (run migration 0008).
final voiceAssignmentsProvider =
    FutureProvider<Map<String, VoiceAssignment>>((ref) async {
  try {
    return await ref.watch(voiceAssignmentRepositoryProvider).loadAll();
  } catch (_) {
    return <String, VoiceAssignment>{};
  }
});
