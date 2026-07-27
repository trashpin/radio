/// The pipeline state for one AI content stage on a destination.
enum DestinationStatus {
  pending('pending', 'Pending'),
  inProgress('in_progress', 'In progress'),
  complete('complete', 'Complete');

  const DestinationStatus(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static DestinationStatus fromDb(String? v) {
    switch ((v ?? '').toLowerCase()) {
      case 'complete':
      case 'completed':
      case 'done':
        return DestinationStatus.complete;
      case 'in_progress':
      case 'running':
      case 'researching':
        return DestinationStatus.inProgress;
      default:
        return DestinationStatus.pending;
    }
  }
}

/// The full "Master Destination" record backing the admin dashboard. Mirrors the
/// live `destinations` table (Base44 schema) plus the columns added by migration
/// `0020_master_destinations.sql`.
class MasterDestination {
  const MasterDestination({
    required this.id,
    required this.name,
    this.code,
    this.slug,
    this.type,
    this.subcategory,
    this.state,
    this.county,
    this.city,
    this.region,
    this.managingAgency,
    this.latitude,
    this.longitude,
    this.published = false,
    this.featured = false,
    this.aiEnabled = true,
    this.priority = 0,
    this.researchStatus = DestinationStatus.pending,
    this.storyStatus = DestinationStatus.pending,
    this.audioStatus = DestinationStatus.pending,
    this.imageStatus = DestinationStatus.pending,
    this.videoStatus = DestinationStatus.pending,
    this.storyCount = 0,
    this.audioCount = 0,
    this.imageCount = 0,
    this.playCount = 0,
    this.updatedAt,
    this.lastAiResearch,
    this.lastStoryGeneration,
    this.lastAudioGeneration,
  });

  final String id;
  final String name;
  final String? code;
  final String? slug;
  final String? type;
  final String? subcategory;
  final String? state;
  final String? county;
  final String? city;
  final String? region;
  final String? managingAgency;
  final double? latitude;
  final double? longitude;
  final bool published;
  final bool featured;
  final bool aiEnabled;
  final int priority;
  final DestinationStatus researchStatus;
  final DestinationStatus storyStatus;
  final DestinationStatus audioStatus;
  final DestinationStatus imageStatus;
  final DestinationStatus videoStatus;
  final int storyCount;
  final int audioCount;
  final int imageCount;
  final int playCount;
  final DateTime? updatedAt;
  final DateTime? lastAiResearch;
  final DateTime? lastStoryGeneration;
  final DateTime? lastAudioGeneration;

  bool get gpsReady => latitude != null && longitude != null;

  factory MasterDestination.fromJson(Map<String, dynamic> j) {
    int asInt(dynamic v) => (v as num?)?.toInt() ?? 0;
    double? asDouble(dynamic v) => (v as num?)?.toDouble();
    DateTime? asDate(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());
    return MasterDestination(
      id: (j['destination_id'] ?? j['id'] ?? '').toString(),
      name: (j['name'] ?? '') as String,
      code: j['destination_code'] as String?,
      slug: j['slug'] as String?,
      type: (j['destination_type'] ?? j['category']) as String?,
      subcategory: j['subcategory'] as String?,
      state: j['state_province'] as String?,
      county: j['county'] as String?,
      city: j['city'] as String?,
      region: j['region'] as String?,
      managingAgency: j['managing_agency'] as String?,
      latitude: asDouble(j['latitude']),
      longitude: asDouble(j['longitude']),
      published: (j['published'] ?? false) as bool,
      featured: (j['featured'] ?? false) as bool,
      aiEnabled: (j['ai_enabled'] ?? true) as bool,
      priority: asInt(j['priority']),
      researchStatus: DestinationStatus.fromDb(j['research_status'] as String?),
      storyStatus: DestinationStatus.fromDb(j['story_status'] as String?),
      audioStatus: DestinationStatus.fromDb(j['audio_status'] as String?),
      imageStatus: DestinationStatus.fromDb(j['image_status'] as String?),
      videoStatus: DestinationStatus.fromDb(j['video_status'] as String?),
      storyCount: asInt(j['story_count']),
      audioCount: asInt(j['audio_count']),
      imageCount: asInt(j['image_count']),
      playCount: asInt(j['play_count']),
      updatedAt: asDate(j['updated_at']),
      lastAiResearch: asDate(j['last_ai_research']),
      lastStoryGeneration: asDate(j['last_story_generation']),
      lastAudioGeneration: asDate(j['last_audio_generation']),
    );
  }
}

/// The AI jobs an admin can launch for a destination. Each maps to a
/// `generation_jobs.job_type` and (optionally) the destination status column it
/// advances to `in_progress` immediately for dashboard feedback.
enum DestinationAiJob {
  research('research', 'Research Destination', 'research_status'),
  stories('stories', 'Generate Stories', 'story_status'),
  narration('audio', 'Generate Narration', 'audio_status'),
  stationSegments('station_segments', 'Generate Station Segments', null),
  wildlife('wildlife_facts', 'Generate Wildlife Facts', null),
  plants('plant_facts', 'Generate Plant Facts', null),
  history('history', 'Generate History', null),
  scenicDrive('scenic_commentary', 'Generate Scenic Drive Commentary', null),
  full('full', 'Full Pipeline', 'research_status');

  const DestinationAiJob(this.jobType, this.label, this.statusColumn);
  final String jobType;
  final String label;
  final String? statusColumn;
}
