import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_boundary.dart';
import 'package:explorer_os_mobile/features/ocala_forest/tour/models/tour_subject.dart';

/// The only two ranger-district admin org codes the imported trail dataset
/// uses (the SAME decode `forest-trail-audio` already applies server-side)
/// — resolved here so the tour's spoken narration can say "the Lake George
/// Ranger District" instead of a raw code, without inventing a meaning for
/// any other code.
String? managingOrgLabel(String? code) {
  switch (code) {
    case '080502':
      return 'the Lake George Ranger District';
    case '080505':
      return 'the Seminole Ranger District';
    default:
      return null;
  }
}

/// One generated tour segment — a real result from the `forest-tour` Edge
/// Function. [storyType] is always the SAME classification the request
/// sent in (echoed back by the function, never re-derived by the AI) — see
/// `TourStoryType`.
class TourNarrationResult {
  const TourNarrationResult({
    required this.text,
    required this.storyType,
    required this.audioUrl,
    required this.durationSeconds,
  });
  final String text;
  final String storyType;
  final String? audioUrl;
  final double? durationSeconds;
}

/// Client for the `forest-tour` Edge Function (spec §5/§6) — assembles the
/// structured context from a [TourSubject] (already selected by
/// [ForestTourEngine]/[TourSubjectSelector], reusing the existing GPS/
/// geofence/trail infrastructure) and requests one narrated segment.
class ForestTourNarrationService {
  const ForestTourNarrationService();

  Future<TourNarrationResult?> requestIntro({ForestBoundary? forest}) {
    return _call({
      'segmentKind': 'intro',
      if (forest != null) 'forestIdentity': {'name': forest.name, 'acres': forest.acres},
    });
  }

  Future<TourNarrationResult?> requestForSubject(
    TourSubject subject, {
    ForestBoundary? forest,
    List<String> nearbySummary = const [],
    List<String> recentlyMentioned = const [],
    double? gpsAccuracyMeters,
  }) {
    final body = <String, dynamic>{
      if (forest != null) 'forestIdentity': {'name': forest.name, 'acres': forest.acres},
      if (nearbySummary.isNotEmpty) 'nearbySummary': nearbySummary,
      if (recentlyMentioned.isNotEmpty) 'recentlyMentionedNames': recentlyMentioned,
      // spec §18/§19: the AI must never claim more geographic precision
      // than the data actually supports.
      'isExactMatch': subject.isExactMatch,
      'gpsAccuracyMeters': ?gpsAccuracyMeters,
    };

    switch (subject.kind) {
      case TourSubjectKind.trail:
        final t = subject.trail!;
        body['segmentKind'] = 'trail';
        body['trailSubject'] = {
          'name': subject.name,
          if (t.trailNo.trim().isNotEmpty) 'trailNo': t.trailNo,
          if (t.lengthMiles != null) 'lengthMiles': t.lengthMiles,
          if (t.trailType != null) 'trailType': t.trailType,
          if (t.trailSurface != null) 'trailSurface': t.trailSurface,
          if (t.accessibilityStatus != null) 'accessibilityStatus': t.accessibilityStatus,
          if (t.nationalTrailDesignation != null)
            'nationalTrailDesignation': t.nationalTrailDesignation,
          if (managingOrgLabel(t.managingOrg) != null)
            'managingOrgLabel': managingOrgLabel(t.managingOrg),
        };
      case TourSubjectKind.location:
        final l = subject.location!;
        body['segmentKind'] = 'location';
        body['locationSubject'] = {
          'name': subject.name,
          'category': l.category,
          if (l.description != null) 'description': l.description,
          if (l.narrationShort != null) 'narrationShort': l.narrationShort,
          'storyType': subject.storyType.id,
        };
      case TourSubjectKind.general:
        body['segmentKind'] = 'general';
    }

    return _call(body);
  }

  Future<TourNarrationResult?> _call(Map<String, dynamic> body) async {
    if (!SupabaseService.isConfigured) return null;
    try {
      final res = await SupabaseService.client.functions
          .invoke('forest-tour', body: body)
          .timeout(const Duration(seconds: 45));
      final data = res.data;
      if (data is Map) {
        final text = (data['text'] as String?)?.trim();
        if (text != null && text.isNotEmpty) {
          return TourNarrationResult(
            text: text,
            storyType: (data['storyType'] as String?) ?? 'general',
            audioUrl: data['audioUrl'] as String?,
            durationSeconds: (data['durationSeconds'] as num?)?.toDouble(),
          );
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

final forestTourNarrationServiceProvider =
    Provider<ForestTourNarrationService>((ref) => const ForestTourNarrationService());
