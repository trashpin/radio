// Unit tests for ForestTrail.fromJson's GeoJSON-parts parsing — the one
// genuinely pure piece of client-side logic added by the v3 official-trail
// import (the rest of the import/grouping logic lives server-side in
// migration 0050_ocala_forest_trails.sql + the ocala-trails-import edge
// function, verified directly against the live database instead).

import 'package:explorer_os_mobile/features/ocala_forest/models/forest_trail.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ForestTrail.fromJson', () {
    test('parses a MultiLineString geom_geojson into parts of lat/lng points', () {
      final trail = ForestTrail.fromJson({
        'id': 't1',
        'forest_id': 'f1',
        'trail_no': '0520',
        'trail_name': 'CENTENNIAL TRAIL',
        'length_miles': 36.262,
        'segment_count': 34,
        'geom_geojson':
            '{"type":"MultiLineString","coordinates":[[[-81.1,29.1],[-81.2,29.2]],[[-81.3,29.3],[-81.4,29.4],[-81.5,29.5]]]}',
      });

      expect(trail.trailNo, '0520');
      expect(trail.trailName, 'CENTENNIAL TRAIL');
      expect(trail.lengthMiles, 36.262);
      expect(trail.segmentCount, 34);
      expect(trail.parts, hasLength(2));
      expect(trail.parts[0], hasLength(2));
      expect(trail.parts[0][0].lat, 29.1);
      expect(trail.parts[0][0].lng, -81.1);
      expect(trail.parts[1], hasLength(3));
    });

    test('never invents a value for a field the source omitted', () {
      final trail = ForestTrail.fromJson({
        'id': 't2',
        'forest_id': 'f1',
        'trail_no': '0001',
      });

      expect(trail.trailName, isNull);
      expect(trail.lengthMiles, isNull);
      expect(trail.trailType, isNull);
      expect(trail.managingOrg, isNull);
      expect(trail.geometricStartLat, isNull);
      expect(trail.parts, isEmpty);
    });

    test('degrades to no geometry rather than throwing on malformed geom_geojson', () {
      final trail = ForestTrail.fromJson({
        'id': 't3',
        'forest_id': 'f1',
        'trail_no': '0002',
        'geom_geojson': 'not valid json',
      });

      expect(trail.parts, isEmpty);
    });

    test('hasGeometricStart is true only when both coordinates are present', () {
      final withStart = ForestTrail.fromJson({
        'id': 't4',
        'forest_id': 'f1',
        'trail_no': '0003',
        'geometric_start_lat': 29.0,
        'geometric_start_lng': -81.5,
      });
      final withoutStart = ForestTrail.fromJson({
        'id': 't5',
        'forest_id': 'f1',
        'trail_no': '0004',
      });

      expect(withStart.hasGeometricStart, isTrue);
      expect(withoutStart.hasGeometricStart, isFalse);
    });

    test('hasOfficialMap/hasReadyAudio are false by default, never assumed true', () {
      final trail = ForestTrail.fromJson({'id': 't6', 'forest_id': 'f1', 'trail_no': '0006'});
      expect(trail.hasOfficialMap, isFalse);
      expect(trail.hasReadyAudio, isFalse);
      expect(trail.audioStatus, 'none');
    });

    test('parses map and audio fields when present', () {
      final trail = ForestTrail.fromJson({
        'id': 't7',
        'forest_id': 'f1',
        'trail_no': '0520',
        'map_image_url': 'https://example.com/map.jpg',
        'map_source_name': 'U.S. Forest Service',
        'map_source_url': 'https://fs.usda.gov/example',
        'map_retrieved_at': '2026-08-01T00:00:00Z',
        'map_document_id': 'DOC-123',
        'audio_script': 'Welcome to the trail.',
        'audio_voice_id': 'voice123',
        'audio_url': 'https://example.com/audio.mp3',
        'audio_duration_seconds': 29,
        'audio_generated_at': '2026-08-01T00:00:00Z',
        'audio_status': 'ready',
      });

      expect(trail.hasOfficialMap, isTrue);
      expect(trail.mapSourceName, 'U.S. Forest Service');
      expect(trail.mapDocumentId, 'DOC-123');
      expect(trail.hasReadyAudio, isTrue);
      expect(trail.audioDurationSeconds, 29);
      expect(trail.audioScript, 'Welcome to the trail.');
    });

    test('hasReadyAudio is false when status is ready but url is missing', () {
      final trail = ForestTrail.fromJson({
        'id': 't8',
        'forest_id': 'f1',
        'trail_no': '0007',
        'audio_status': 'ready',
      });
      expect(trail.hasReadyAudio, isFalse);
    });
  });

  group('ForestTrail.copyWithAudio', () {
    test('updates only audio fields, preserving every other field', () {
      final original = ForestTrail.fromJson({
        'id': 't9',
        'forest_id': 'f1',
        'trail_no': '0520',
        'trail_name': 'CENTENNIAL TRAIL',
        'length_miles': 36.262,
      });

      final updated = original.copyWithAudio(
        audioUrl: 'https://example.com/a.mp3',
        audioScript: 'Hello',
        audioDurationSeconds: 30,
        audioStatus: 'ready',
      );

      expect(updated.trailName, 'CENTENNIAL TRAIL');
      expect(updated.lengthMiles, 36.262);
      expect(updated.hasReadyAudio, isTrue);
      expect(updated.audioScript, 'Hello');
      expect(updated.audioDurationSeconds, 30);
    });
  });
}
