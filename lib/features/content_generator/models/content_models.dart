/// The kinds of destinations the content engine supports.
enum DestinationCategory {
  nationalPark('national_park', 'National Park'),
  statePark('state_park', 'State Park'),
  nationalForest('national_forest', 'National Forest'),
  county('county', 'County'),
  city('city', 'City'),
  historicDistrict('historic_district', 'Historic District'),
  scenicHighway('scenic_highway', 'Scenic Highway'),
  spring('spring', 'Spring'),
  river('river', 'River'),
  lake('lake', 'Lake'),
  beach('beach', 'Beach'),
  wildlifeRefuge('wildlife_refuge', 'Wildlife Refuge'),
  museum('museum', 'Museum'),
  attraction('attraction', 'Attraction');

  const DestinationCategory(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static DestinationCategory fromDb(String? v) =>
      DestinationCategory.values.firstWhere((e) => e.dbValue == v,
          orElse: () => DestinationCategory.nationalPark);
}

/// The stages a generation job moves through.
enum JobStatus {
  pending('pending', 'Pending'),
  researching('researching', 'Researching'),
  buildingKnowledge('building_knowledge', 'Building Knowledge'),
  generatingStories('generating_stories', 'Generating Stories'),
  generatingAudio('generating_audio', 'Generating Audio'),
  waitingForReview('waiting_for_review', 'Waiting for Review'),
  completed('completed', 'Completed'),
  failed('failed', 'Failed');

  const JobStatus(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static JobStatus fromDb(String? v) => JobStatus.values
      .firstWhere((e) => e.dbValue == v, orElse: () => JobStatus.pending);

  bool get isTerminal => this == completed || this == failed;
}

/// What a job should do.
enum JobType {
  research('research', 'Research'),
  knowledge('knowledge', 'Build Knowledge'),
  stories('stories', 'Generate Stories'),
  audio('audio', 'Generate Audio'),
  full('full', 'Full Pipeline'),
  bulk('bulk', 'Bulk Region');

  const JobType(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static JobType fromDb(String? v) =>
      JobType.values.firstWhere((e) => e.dbValue == v, orElse: () => JobType.research);
}

/// One researched fact (mirrors `knowledge_base`).
class KnowledgeFact {
  const KnowledgeFact({
    required this.id,
    required this.destination,
    required this.category,
    required this.title,
    this.destinationCategory,
    this.description,
    this.source,
    this.latitude,
    this.longitude,
    this.confidenceScore = 0.7,
    this.verified = false,
    this.approved = false,
  });

  final String id;
  final String destination;
  final String category;
  final String title;
  final String? destinationCategory;
  final String? description;
  final String? source;
  final double? latitude;
  final double? longitude;
  final double confidenceScore;
  final bool verified;
  final bool approved;

  factory KnowledgeFact.fromJson(Map<String, dynamic> j) => KnowledgeFact(
        id: (j['id'] ?? '').toString(),
        destination: (j['destination'] ?? '') as String,
        category: (j['category'] ?? 'General') as String,
        title: (j['title'] ?? '') as String,
        destinationCategory: j['destination_category'] as String?,
        description: j['description'] as String?,
        source: j['source'] as String?,
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        confidenceScore: (j['confidence_score'] as num?)?.toDouble() ?? 0.7,
        verified: (j['verified'] ?? false) as bool,
        approved: (j['approved'] ?? false) as bool,
      );

  Map<String, dynamic> toInsert() => {
        'destination': destination,
        'category': category,
        'title': title,
        if (destinationCategory != null) 'destination_category': destinationCategory,
        if (description != null) 'description': description,
        if (source != null) 'source': source,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'confidence_score': confidenceScore,
        'verified': verified,
        'approved': approved,
      };
}

/// A background content-generation job (mirrors `generation_jobs`).
class GenerationJob {
  const GenerationJob({
    required this.id,
    required this.destination,
    required this.jobType,
    required this.status,
    this.destinationCategory,
    this.state,
    this.county,
    this.latitude,
    this.longitude,
    this.radiusM = 150,
    this.progress = 0,
    this.message,
    this.notes,
    this.website,
    this.createdAt,
  });

  final String id;
  final String destination;
  final JobType jobType;
  final JobStatus status;
  final String? destinationCategory;
  final String? state;
  final String? county;
  final double? latitude;
  final double? longitude;
  final int radiusM;
  final int progress;
  final String? message;
  final String? notes;
  final String? website;
  final DateTime? createdAt;

  factory GenerationJob.fromJson(Map<String, dynamic> j) => GenerationJob(
        id: (j['id'] ?? '').toString(),
        destination: (j['destination'] ?? '') as String,
        jobType: JobType.fromDb(j['job_type'] as String?),
        status: JobStatus.fromDb(j['status'] as String?),
        destinationCategory: j['destination_category'] as String?,
        state: j['state'] as String?,
        county: j['county'] as String?,
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        radiusM: (j['radius_m'] as num?)?.toInt() ?? 150,
        progress: (j['progress'] as num?)?.toInt() ?? 0,
        message: j['message'] as String?,
        notes: j['notes'] as String?,
        website: j['website'] as String?,
        createdAt: DateTime.tryParse((j['created_at'] ?? '') as String? ?? ''),
      );

  Map<String, dynamic> toInsert() => {
        'destination': destination,
        'job_type': jobType.dbValue,
        'status': status.dbValue,
        if (destinationCategory != null) 'destination_category': destinationCategory,
        if (state != null) 'state': state,
        if (county != null) 'county': county,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'radius_m': radiusM,
        'progress': progress,
        if (message != null) 'message': message,
        if (notes != null) 'notes': notes,
        if (website != null) 'website': website,
      };
}
