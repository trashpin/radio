import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/shared/models/knowledge_article.dart';
import 'package:explorer_os_mobile/shared/models/stop.dart';
import 'package:explorer_os_mobile/shared/models/story.dart';

void main() {
  test('Stop.fromJson maps the Base44 stops schema', () {
    final s = Stop.fromJson({
      'stop_id': 'st-1',
      'destination_id': 'dest-1',
      'stop_name': 'Juniper Springs',
      'stop_type': 'spring',
      'short_description': 'A clear spring.',
      'hero_image': 'https://img/juniper.jpg',
      'latitude': 29.18,
      'longitude': -81.71,
      'sort_order': 3,
      'audio_available': true,
      'gps_trigger_radius_meters': 150,
    });
    expect(s.id, 'st-1');
    expect(s.parkId, 'dest-1'); // destination_id
    expect(s.name, 'Juniper Springs');
    expect(s.stopType, 'spring');
    expect(s.description, 'A clear spring.');
    expect(s.imageUrl, 'https://img/juniper.jpg');
    expect(s.orderIndex, 3);
    expect(s.audioAvailable, isTrue);
    expect(s.triggerRadiusMeters, 150);
  });

  test('Stop.fromJson still accepts legacy keys', () {
    final s = Stop.fromJson({
      'id': 'legacy',
      'park_id': 'p1',
      'name': 'Old Stop',
      'image_url': 'u',
      'order_index': 1,
    });
    expect(s.id, 'legacy');
    expect(s.parkId, 'p1');
    expect(s.name, 'Old Stop');
    expect(s.orderIndex, 1);
  });

  test('Story.fromJson maps the Base44 stories schema', () {
    final s = Story.fromJson({
      'story_id': 'sy-1',
      'destination_id': 'dest-1',
      'stop_id': 'st-1',
      'title': 'The Springs of Ocala',
      'story_category': 'history',
      'short_summary': 'Short.',
      'full_story': 'Long story body.',
      'voice_script': 'Narrator: ...',
      'hero_media_id': 'md-1',
    });
    expect(s.id, 'sy-1');
    expect(s.parkId, 'dest-1');
    expect(s.stopId, 'st-1');
    expect(s.title, 'The Springs of Ocala');
    expect(s.category, 'history');
    expect(s.shortSummary, 'Short.');
    expect(s.body, 'Long story body.'); // prefers full_story
    expect(s.voiceScript, 'Narrator: ...');
    expect(s.heroMediaId, 'md-1');
  });

  test('KnowledgeArticle.fromJson maps the Base44 knowledge_articles schema',
      () {
    final k = KnowledgeArticle.fromJson({
      'knowledge_id': 'kn-1',
      'destination_id': 'dest-1',
      'stop_id': 'st-1',
      'title': 'Sand Pine Scrub',
      'category': 'ecology',
      'summary': 'Summary.',
      'content': 'Full content.',
      'voice_script': 'Narrator: ...',
      'hero_media_id': 'md-2',
      'reading_time_minutes': 4,
      'audio_length_seconds': 120,
      'published': true,
      'sort_order': 2,
    });
    expect(k.id, 'kn-1');
    expect(k.destinationId, 'dest-1');
    expect(k.stopId, 'st-1');
    expect(k.title, 'Sand Pine Scrub');
    expect(k.category, 'ecology');
    expect(k.content, 'Full content.');
    expect(k.voiceScript, 'Narrator: ...');
    expect(k.heroMediaId, 'md-2');
    expect(k.readingTimeMinutes, 4);
    expect(k.audioLengthSeconds, 120);
    expect(k.published, isTrue);
    expect(k.sortOrder, 2);
  });
}
