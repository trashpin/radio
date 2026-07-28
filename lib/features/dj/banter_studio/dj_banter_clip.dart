import 'package:explorer_os_mobile/features/dj/banter_studio/banter_category.dart';

/// A single DJ banter clip from the `dj_banter` library.
///
/// The `text` may contain `{placeholders}` (e.g. `{upcoming_attraction}`,
/// `{county}`, `{road}`, `{nearby_wildlife}`) which the [GpsBanterDirector]
/// fills from live GPS context at playback time — so a stored line still sounds
/// specific to where the visitor actually is.
class DjBanterClip {
  const DjBanterClip({
    required this.id,
    required this.category,
    required this.text,
    this.destinationId,
    this.destinationCode,
    this.audioUrl,
    this.voiceId,
    this.voiceName,
    this.duration,
    this.gpsRegion,
    this.latitude,
    this.longitude,
    this.radiusM,
    this.guideMode,
    this.status = BanterStatus.draft,
    this.tags = const [],
    this.lastPlayed,
    this.playCount = 0,
    this.tripPlayed = 0,
    this.destinationPlayed = 0,
    this.version = 1,
  });

  final String id;
  final BanterCategory category;
  final String text;
  final String? destinationId;
  final String? destinationCode;
  final String? audioUrl;
  final String? voiceId;
  final String? voiceName;
  final double? duration;
  final String? gpsRegion;
  final double? latitude;
  final double? longitude;
  final double? radiusM;
  final String? guideMode;
  final BanterStatus status;
  final List<String> tags;
  final DateTime? lastPlayed;
  final int playCount;
  final int tripPlayed;
  final int destinationPlayed;
  final int version;

  bool get hasAudio => (audioUrl ?? '').trim().isNotEmpty;
  bool get isPublished => status == BanterStatus.published;

  static double? _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');
  static List<String> _tags(dynamic v) =>
      v is List ? v.map((e) => e.toString()).toList() : const [];

  factory DjBanterClip.fromJson(Map<String, dynamic> j) => DjBanterClip(
        id: (j['id'] ?? '').toString(),
        category: BanterCategory.fromId(j['category'] as String?) ??
            BanterCategory.stationId,
        text: (j['text'] ?? '') as String,
        destinationId: j['destination_id']?.toString(),
        destinationCode: j['destination_code'] as String?,
        audioUrl: j['audio_url'] as String?,
        voiceId: j['voice_id'] as String?,
        voiceName: j['voice_name'] as String?,
        duration: _d(j['duration']),
        gpsRegion: j['gps_region'] as String?,
        latitude: _d(j['latitude']),
        longitude: _d(j['longitude']),
        radiusM: _d(j['radius_m']),
        guideMode: j['guide_mode'] as String?,
        status: BanterStatus.fromId(j['status'] as String?),
        tags: _tags(j['tags']),
        lastPlayed: DateTime.tryParse('${j['last_played']}'),
        playCount: (j['play_count'] as num?)?.toInt() ?? 0,
        tripPlayed: (j['trip_played'] as num?)?.toInt() ?? 0,
        destinationPlayed: (j['destination_played'] as num?)?.toInt() ?? 0,
        version: (j['version'] as num?)?.toInt() ?? 1,
      );

  /// Column map for insert/update (id/timestamps managed by the DB).
  Map<String, dynamic> toWrite() => {
        if (destinationId != null) 'destination_id': destinationId,
        'destination_code': destinationCode,
        'category': category.id,
        'text': text,
        'audio_url': audioUrl,
        'voice_id': voiceId,
        'voice_name': voiceName,
        'duration': duration,
        'gps_region': gpsRegion,
        'latitude': latitude,
        'longitude': longitude,
        'radius_m': radiusM,
        'guide_mode': guideMode,
        'status': status.id,
        'tags': tags,
        'version': version,
      };

  DjBanterClip copyWith({
    BanterCategory? category,
    String? text,
    String? destinationId,
    String? destinationCode,
    String? audioUrl,
    String? voiceId,
    String? voiceName,
    double? duration,
    String? gpsRegion,
    double? latitude,
    double? longitude,
    double? radiusM,
    String? guideMode,
    BanterStatus? status,
    List<String>? tags,
    int? version,
  }) =>
      DjBanterClip(
        id: id,
        category: category ?? this.category,
        text: text ?? this.text,
        destinationId: destinationId ?? this.destinationId,
        destinationCode: destinationCode ?? this.destinationCode,
        audioUrl: audioUrl ?? this.audioUrl,
        voiceId: voiceId ?? this.voiceId,
        voiceName: voiceName ?? this.voiceName,
        duration: duration ?? this.duration,
        gpsRegion: gpsRegion ?? this.gpsRegion,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        radiusM: radiusM ?? this.radiusM,
        guideMode: guideMode ?? this.guideMode,
        status: status ?? this.status,
        tags: tags ?? this.tags,
        lastPlayed: lastPlayed,
        playCount: playCount,
        tripPlayed: tripPlayed,
        destinationPlayed: destinationPlayed,
        version: version ?? this.version,
      );
}

/// One entry in a clip's edit history (`dj_banter_versions`).
class DjBanterVersion {
  const DjBanterVersion({
    required this.id,
    required this.banterId,
    required this.version,
    this.text,
    this.voiceId,
    this.voiceName,
    this.author,
    this.createdAt,
  });

  final String id;
  final String banterId;
  final int version;
  final String? text;
  final String? voiceId;
  final String? voiceName;
  final String? author;
  final DateTime? createdAt;

  factory DjBanterVersion.fromJson(Map<String, dynamic> j) => DjBanterVersion(
        id: (j['id'] ?? '').toString(),
        banterId: (j['banter_id'] ?? '').toString(),
        version: (j['version'] as num?)?.toInt() ?? 1,
        text: j['text'] as String?,
        voiceId: j['voice_id'] as String?,
        voiceName: j['voice_name'] as String?,
        author: j['author'] as String?,
        createdAt: DateTime.tryParse('${j['created_at']}'),
      );
}
