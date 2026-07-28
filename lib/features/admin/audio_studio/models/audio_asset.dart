import 'package:explorer_os_mobile/core/data/model.dart';

/// Current narration generation version. Assets produced with an older version
/// are flagged "outdated" by the auditor and can be regenerated.
const int kAudioGenerationVersion = 1;

/// TTS providers the studio can target. Selectable without code changes — the
/// provider is stored on each asset and in settings.
enum TtsProvider {
  elevenlabs('elevenlabs', 'ElevenLabs'),
  openai('openai', 'OpenAI TTS'),
  google('google', 'Google Cloud TTS'),
  polly('polly', 'Amazon Polly'),
  azure('azure', 'Azure Speech');

  const TtsProvider(this.id, this.label);
  final String id;
  final String label;

  static TtsProvider fromId(String? id) => values.firstWhere(
        (p) => p.id == (id ?? '').toLowerCase(),
        orElse: () => TtsProvider.elevenlabs,
      );
}

/// The content/voice categories that get a default voice assigned in the Voice
/// Library, each mapped to a Storage folder.
enum VoiceCategory {
  parkWelcome('park_welcome', 'Park Welcome', 'parks'),
  wildlife('wildlife', 'Wildlife', 'wildlife'),
  birds('birds', 'Birds', 'birds'),
  fish('fish', 'Fish', 'fish'),
  reptiles('reptiles', 'Reptiles', 'reptiles'),
  plants('plants', 'Plants', 'plants'),
  history('history', 'History', 'history'),
  stories('stories', 'Stories', 'stories'),
  safety('safety', 'Safety', 'safety'),
  radio('radio', 'Radio', 'radio'),
  children('children', 'Children', 'stories');

  const VoiceCategory(this.id, this.label, this.folder);
  final String id;
  final String label;
  final String folder;

  /// Maps a free-form record category token to a [VoiceCategory].
  static VoiceCategory fromToken(String? token) {
    final t = (token ?? '').toLowerCase();
    if (t.contains('bird')) return VoiceCategory.birds;
    if (t.contains('fish')) return VoiceCategory.fish;
    if (t.contains('reptile') || t.contains('amphib')) {
      return VoiceCategory.reptiles;
    }
    if (t.contains('animal') || t.contains('mammal') || t.contains('wildlife')) {
      return VoiceCategory.wildlife;
    }
    if (t.contains('plant') ||
        t.contains('tree') ||
        t.contains('flower') ||
        t.contains('wildflower')) {
      return VoiceCategory.plants;
    }
    if (t.contains('history') || t.contains('historic')) {
      return VoiceCategory.history;
    }
    if (t.contains('story') || t.contains('stories')) {
      return VoiceCategory.stories;
    }
    if (t.contains('safety')) return VoiceCategory.safety;
    if (t.contains('radio')) return VoiceCategory.radio;
    return VoiceCategory.parkWelcome;
  }
}

/// Lifecycle status of an audio asset.
enum AudioStatus {
  pending,
  generating,
  complete,
  failed;

  static AudioStatus fromString(String? s) {
    switch ((s ?? 'pending').toLowerCase()) {
      case 'generating':
        return AudioStatus.generating;
      case 'complete':
      case 'completed':
      case 'done':
        return AudioStatus.complete;
      case 'failed':
      case 'error':
        return AudioStatus.failed;
      default:
        return AudioStatus.pending;
    }
  }

  String get label => switch (this) {
        AudioStatus.pending => 'Pending',
        AudioStatus.generating => 'Generating',
        AudioStatus.complete => 'Complete',
        AudioStatus.failed => 'Failed',
      };
}

/// A generated narration audio file (`audio_assets` row).
class AudioAsset implements Model {
  const AudioAsset({
    required this.id,
    this.recordId,
    this.recordType,
    this.destinationCode,
    this.category,
    this.voice,
    this.voiceName,
    this.provider = TtsProvider.elevenlabs,
    this.language = 'en',
    this.storagePath,
    this.publicUrl,
    this.duration,
    this.fileSize,
    this.generationVersion = 1,
    this.status = AudioStatus.pending,
    this.generatedAt,
  });

  @override
  final String id;
  final String? recordId;
  final String? recordType;
  final String? destinationCode;
  final String? category;
  final String? voice;
  final String? voiceName;
  final TtsProvider provider;
  final String language;
  final String? storagePath;
  final String? publicUrl;
  final double? duration;
  final int? fileSize;
  final int generationVersion;
  final AudioStatus status;
  final DateTime? generatedAt;

  bool get hasFile => (publicUrl ?? '').isNotEmpty;
  bool get isZeroByte => fileSize != null && fileSize == 0;
  bool get isOutdated => generationVersion < kAudioGenerationVersion;

  factory AudioAsset.fromJson(Json j) => AudioAsset(
        id: (j['id'] ?? '').toString(),
        recordId: j['record_id']?.toString(),
        recordType: j['record_type'] as String?,
        destinationCode: j['destination_code'] as String?,
        category: j['category'] as String?,
        voice: j['voice'] as String?,
        voiceName: j['voice_name'] as String?,
        provider: TtsProvider.fromId(j['provider'] as String?),
        language: (j['language'] ?? 'en') as String,
        storagePath: j['storage_path'] as String?,
        publicUrl: j['public_url'] as String?,
        duration: (j['duration'] as num?)?.toDouble(),
        fileSize: (j['file_size'] as num?)?.toInt(),
        generationVersion: (j['generation_version'] as num?)?.toInt() ?? 1,
        status: AudioStatus.fromString(j['status'] as String?),
        generatedAt: DateTime.tryParse(j['generated_at']?.toString() ?? ''),
      );
}
