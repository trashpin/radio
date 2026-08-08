import 'package:explorer_os_mobile/features/radio_automation/models/radio_schedule_rule.dart';
import 'package:explorer_os_mobile/features/radio_automation/models/radio_segment.dart';
import 'package:explorer_os_mobile/features/radio_automation/services/announcement_content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('announcement adapters (Scheduler Reconciliation Step 1)', () {
    test('safety message → safety segment (all-station, published, has audio)',
        () {
      final s = safetyMessageToSegment({
        'id': 's1',
        'title': 'Watch for bears',
        'audio_url': 'https://a/safety.mp3',
      })!;
      expect(s.id, 'safety:s1');
      expect(s.category, SegmentCategory.safety);
      expect(s.station, 'all');
      expect(s.published, isTrue);
      expect(s.hasAudio, isTrue);
      expect(s.generatedByAi, isFalse);
      expect(s.title, 'Watch for bears');
    });

    test('wildlife alert → wildlifeIntro segment', () {
      final s = wildlifeAlertToSegment(
          {'id': 'w1', 'audio_url': 'https://a/w.mp3'})!;
      expect(s.id, 'wildlife:w1');
      expect(s.category, SegmentCategory.wildlifeIntro);
      expect(s.title, 'Wildlife update'); // fallback title
    });

    test('story → story segment, prefers story_id', () {
      final s = storyToSegment({
        'id': 'row9',
        'story_id': 'story9',
        'title': 'River of Grass',
        'audio_url': 'https://a/story.mp3',
      })!;
      expect(s.id, 'story:story9');
      expect(s.category, SegmentCategory.story);
      expect(s.title, 'River of Grass');
    });

    test('rows without playable audio are dropped', () {
      expect(safetyMessageToSegment({'id': 's', 'audio_url': null}), isNull);
      expect(safetyMessageToSegment({'id': 's', 'audio_url': '  '}), isNull);
      expect(wildlifeAlertToSegment({'audio_url': 'https://a/w.mp3'}), isNull);
    });
  });

  test('combineAnnouncementContent unifies all sources into one pool', () {
    final base = const RadioSegment(
      id: 'seg1',
      title: 'DJ line',
      category: SegmentCategory.djBanter,
      station: 'all',
      audioUrl: 'https://a/dj.mp3',
      published: true,
    );
    final pool = combineAnnouncementContent(
      segments: [base],
      safety: [
        {'id': 's1', 'audio_url': 'https://a/s.mp3'},
        {'id': 'no', 'audio_url': null}, // dropped
      ],
      wildlife: [
        {'id': 'w1', 'audio_url': 'https://a/w.mp3'}
      ],
      stories: [
        {'story_id': 'st1', 'audio_url': 'https://a/st.mp3'}
      ],
    );
    expect(pool.map((s) => s.id).toList(),
        ['seg1', 'safety:s1', 'wildlife:w1', 'story:st1']);
    // Every entry is a published, station-'all', playable RadioSegment the
    // AutomationEngine can select from.
    expect(pool.every((s) => s.published && s.hasAudio), isTrue);
    expect(
        pool.map((s) => s.category).toSet(),
        {
          SegmentCategory.djBanter,
          SegmentCategory.safety,
          SegmentCategory.wildlifeIntro,
          SegmentCategory.story,
        });
  });

  group('legacy radio_schedule rule adapter (Step 2)', () {
    test('interval safety rule → everyXMinutes SAFETY rule', () {
      final r = legacyScheduleRuleToRule({
        'id': 'r1',
        'content_type': 'safety',
        'cadence': 'interval',
        'interval_minutes': 20,
        'priority': 9,
        'active': true,
      })!;
      expect(r.id, 'legacy:r1');
      expect(r.triggerType, TriggerType.everyXMinutes);
      expect(r.triggerValue, 20);
      expect(r.category, SegmentCategory.safety.dbValue);
      expect(r.enabled, isTrue);
      expect(r.station, 'all');
      // Legacy priority 9 (high) inverts to a low automation number (higher).
      expect(r.priority, 91);
    });

    test('content types map to the right categories', () {
      expect(
          legacyScheduleRuleToRule({'id': 'a', 'content_type': 'wildlife'})!
              .category,
          SegmentCategory.wildlifeIntro.dbValue);
      expect(
          legacyScheduleRuleToRule({'id': 'b', 'content_type': 'story'})!
              .category,
          SegmentCategory.story.dbValue);
    });

    test('non-interval cadences + unknown types are ignored (parity)', () {
      // RadioScheduler only ever fired interval rules.
      expect(
          legacyScheduleRuleToRule(
              {'id': 'c', 'content_type': 'safety', 'cadence': 'hourly'}),
          isNull);
      expect(
          legacyScheduleRuleToRule(
              {'id': 'd', 'content_type': 'mystery', 'cadence': 'interval'}),
          isNull);
    });
  });
}
