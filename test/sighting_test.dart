import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/sightings/models/explorer_sighting.dart';
import 'package:explorer_os_mobile/features/sightings/models/sighting_category.dart';
import 'package:explorer_os_mobile/features/sightings/services/ai_ranger_narration_service.dart';

void main() {
  test('SightingCategory token round-trips', () {
    expect(SightingCategory.fromToken('bird'), SightingCategory.bird);
    expect(SightingCategory.fromToken('scenic_view'), SightingCategory.scenicView);
    expect(SightingCategory.fromToken('unknown'), SightingCategory.other);
  });

  test('ExplorerSighting.toJson uses category token and omits nulls', () {
    const s = ExplorerSighting(
      id: 's1',
      category: SightingCategory.bird,
      species: 'Red-shouldered Hawk',
      parkName: 'Ocala National Forest',
      latitude: 29.18,
      longitude: -81.71,
    );
    final json = s.toJson();
    expect(json['category'], 'bird');
    expect(json['species'], 'Red-shouldered Hawk');
    expect(json['latitude'], 29.18);
    expect(json.containsKey('notes'), isFalse); // null omitted
  });

  test('ExplorerSighting.fromJson maps the DB row', () {
    final s = ExplorerSighting.fromJson({
      'sighting_id': 'db-1',
      'category': 'waterfall',
      'species': null,
      'park_name': 'Ocala',
      'latitude': 1.0,
      'longitude': 2.0,
      'created_at': '2026-07-25T02:00:00Z',
    });
    expect(s.id, 'db-1');
    expect(s.category, SightingCategory.waterfall);
    expect(s.hasCoordinates, isTrue);
    expect(s.createdAt, isNotNull);
  });

  test('AiRangerNarrationService gives a friendly reaction (placeholder)', () {
    const svc = AiRangerNarrationService();
    const s = ExplorerSighting(
      id: 's1',
      category: SightingCategory.bird,
      species: 'Red-shouldered Hawk',
      parkName: 'Ocala National Forest',
    );
    final r = svc.reactTo(s);
    expect(r.text, contains('Red-shouldered Hawk'));
    expect(r.text, contains('Ocala National Forest'));
  });
}
