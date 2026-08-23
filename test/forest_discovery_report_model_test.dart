// Unit tests for ForestDiscoveryReport.fromJson — the shape read from the
// forest_discovery_reports_public VIEW (migration 0051). The view itself
// (generalizing coordinates, excluding private/rejected rows) is verified
// directly against the live database; this covers the Dart-side parsing.

import 'package:explorer_os_mobile/features/ocala_forest/discover/models/forest_discovery_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ForestDiscoveryReport.fromJson', () {
    test('parses a fully-populated public row', () {
      final r = ForestDiscoveryReport.fromJson({
        'id': 'd1',
        'forest_id': 'f1',
        'trail_id': 't1',
        'species_id': 's1',
        'category': 'birds',
        'subtype': 'Bird',
        'identification': 'Pileated Woodpecker',
        'scientific_name': 'Dryocopus pileatus',
        'photo_url': 'https://example.com/x.jpg',
        'latitude': 29.1,
        'longitude': -81.6,
        'location_generalized': false,
        'observed_at': '2026-08-22T12:00:00Z',
        'user_notes': 'Saw it near the trailhead.',
        'ai_identification': 'Pileated Woodpecker',
        'ai_scientific_name': 'Dryocopus pileatus',
        'ai_confidence': 'high',
        'ai_explanation': 'Distinct red crest.',
        'user_confirmation': 'accepted',
        'moderation_status': 'pending',
        'is_sensitive': false,
        'source': 'community',
      });

      expect(r.id, 'd1');
      expect(r.displayName, 'Pileated Woodpecker');
      expect(r.locationGeneralized, isFalse);
      expect(r.observedAt, DateTime.utc(2026, 8, 22, 12));
      expect(r.userConfirmation, 'accepted');
    });

    test('never invents a value for a field the row omitted', () {
      final r = ForestDiscoveryReport.fromJson({
        'id': 'd2',
        'category': 'other',
        'photo_url': 'https://example.com/y.jpg',
        'latitude': 29.0,
        'longitude': -81.5,
        'location_generalized': true,
        'observed_at': '2026-08-22T12:00:00Z',
        'user_confirmation': 'unknown',
        'moderation_status': 'pending',
      });

      expect(r.identification, isNull);
      expect(r.scientificName, isNull);
      expect(r.aiIdentification, isNull);
      expect(r.speciesId, isNull);
      expect(r.trailId, isNull);
      expect(r.displayName, 'Unidentified discovery');
      expect(r.locationGeneralized, isTrue);
    });

    test('defaults isSensitive/source sensibly when absent', () {
      final r = ForestDiscoveryReport.fromJson({
        'id': 'd3',
        'category': 'wildlife',
        'photo_url': 'https://example.com/z.jpg',
        'latitude': 29.0,
        'longitude': -81.5,
        'location_generalized': false,
        'observed_at': '2026-08-22T12:00:00Z',
        'user_confirmation': 'unknown',
        'moderation_status': 'pending',
      });

      expect(r.isSensitive, isFalse);
      expect(r.source, 'community');
    });
  });
}
