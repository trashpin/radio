import 'package:explorer_os_mobile/core/data/model.dart';

/// A community-submitted DISCOVER report (spec §8), read from the
/// `forest_discovery_reports_public` VIEW — never the raw
/// `forest_discovery_reports` table, which anon/authenticated clients
/// cannot read directly (see migration 0051's RLS comment). The view
/// already generalizes [latitude]/[longitude] for anything not fully
/// public and excludes private/rejected rows, so every field here is
/// already safe to render as-is.
class ForestDiscoveryReport implements Model {
  const ForestDiscoveryReport({
    required this.id,
    required this.category,
    required this.photoUrl,
    required this.latitude,
    required this.longitude,
    required this.locationGeneralized,
    required this.observedAt,
    required this.moderationStatus,
    required this.userConfirmation,
    this.forestId,
    this.trailId,
    this.speciesId,
    this.subtype,
    this.identification,
    this.scientificName,
    this.userNotes,
    this.aiIdentification,
    this.aiScientificName,
    this.aiConfidence,
    this.aiExplanation,
    this.isSensitive = false,
    this.source = 'community',
  });

  @override
  final String id;
  final String? forestId;
  final String? trailId;
  final String? speciesId;

  final String category;
  final String? subtype;
  final String? identification;
  final String? scientificName;
  final String photoUrl;

  final double latitude;
  final double longitude;

  /// True when [latitude]/[longitude] have already been rounded to a
  /// general area by the view (spec §10) — render "Recently discovered in
  /// this general area" rather than an exact pin when this is true.
  final bool locationGeneralized;

  final DateTime observedAt;
  final String? userNotes;

  final String? aiIdentification;
  final String? aiScientificName;
  final String? aiConfidence;
  final String? aiExplanation;

  /// accepted | edited | unknown (spec §4).
  final String userConfirmation;

  /// pending | confirmed | needs_review | rejected (spec §11) — rejected
  /// rows never reach the client at all (excluded by the view itself), but
  /// the type still allows for it for completeness.
  final String moderationStatus;

  final bool isSensitive;
  final String source;

  String get displayName => (identification?.trim().isNotEmpty ?? false)
      ? identification!.trim()
      : 'Unidentified discovery';

  factory ForestDiscoveryReport.fromJson(Json json) => ForestDiscoveryReport(
        id: json['id']?.toString() ?? '',
        forestId: json['forest_id']?.toString(),
        trailId: json['trail_id']?.toString(),
        speciesId: json['species_id']?.toString(),
        category: (json['category'] ?? '') as String,
        subtype: json['subtype'] as String?,
        identification: json['identification'] as String?,
        scientificName: json['scientific_name'] as String?,
        photoUrl: (json['photo_url'] ?? '') as String,
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        locationGeneralized: json['location_generalized'] as bool? ?? false,
        observedAt: DateTime.tryParse(json['observed_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        userNotes: json['user_notes'] as String?,
        aiIdentification: json['ai_identification'] as String?,
        aiScientificName: json['ai_scientific_name'] as String?,
        aiConfidence: json['ai_confidence'] as String?,
        aiExplanation: json['ai_explanation'] as String?,
        userConfirmation: (json['user_confirmation'] ?? 'unknown') as String,
        moderationStatus: (json['moderation_status'] ?? 'pending') as String,
        isSensitive: json['is_sensitive'] as bool? ?? false,
        source: (json['source'] ?? 'community') as String,
      );
}
