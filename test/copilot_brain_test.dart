// Unit tests for the Travel Copilot's decision engine — pure logic, no
// network/audio, matching the "test text responses before generating audio"
// approach: this is one level earlier still, testing whether the copilot
// decides to speak at all.

import 'package:explorer_os_mobile/features/copilot/data/copilot_session_memory.dart';
import 'package:explorer_os_mobile/features/copilot/models/copilot_event.dart';
import 'package:explorer_os_mobile/features/copilot/models/copilot_priority.dart';
import 'package:explorer_os_mobile/features/copilot/models/copilot_profile.dart';
import 'package:explorer_os_mobile/features/copilot/services/copilot_brain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CopilotBrain', () {
    test('safety/navigation events always speak, even with no quiet time elapsed', () {
      final brain = const CopilotBrain(baseQuietWindow: Duration(seconds: 999));
      final memory = CopilotSessionMemory();
      // Prime memory as if the copilot JUST spoke.
      memory.markSpoken('something-else');

      final event = const CopilotEvent(
        type: CopilotEventType.approachingManeuver,
        coreText: 'Turn right onto Baseline Rd',
      );
      final decision = brain.decide(
        event: event,
        profile: CopilotProfile.empty,
        memory: memory,
      );

      expect(decision.shouldSpeak, isTrue);
      expect(event.tier, CopilotPriorityTier.navigation);
    });

    test('never repeats the exact same event twice in a trip', () {
      final brain = const CopilotBrain();
      final memory = CopilotSessionMemory();
      const event = CopilotEvent(
        type: CopilotEventType.enteringTown,
        placeName: 'Ocklawaha',
      );

      final first = brain.decide(event: event, profile: CopilotProfile.empty, memory: memory);
      expect(first.shouldSpeak, isTrue);
      memory.markSpoken(event.dedupeKey);

      final second = brain.decide(event: event, profile: CopilotProfile.empty, memory: memory);
      expect(second.shouldSpeak, isFalse);
    });

    test('reserved stopSignAhead event type defaults to the safety tier', () {
      const event = CopilotEvent(type: CopilotEventType.stopSignAhead);
      expect(event.tier, CopilotPriorityTier.safety);
    });

    test('background-tier events never map to a playable priority', () {
      expect(CopilotPriorityTier.background.playbackPriority, isNull);
    });

    test('skips an informational event when the traveler has low interest in its topic', () {
      final brain = const CopilotBrain();
      final memory = CopilotSessionMemory();
      final profile = CopilotProfile.empty.withTopicNudged(CopilotTopic.restaurants, up: false);
      const event = CopilotEvent(
        type: CopilotEventType.approachingInterestingLocation,
        placeName: "Joe's Diner",
        typeLabel: 'Restaurant',
      );

      final decision = brain.decide(event: event, profile: profile, memory: memory);
      expect(decision.shouldSpeak, isFalse);
    });

    test('speaks an informational event at default (medium) interest', () {
      final brain = const CopilotBrain();
      final memory = CopilotSessionMemory();
      const event = CopilotEvent(
        type: CopilotEventType.approachingInterestingLocation,
        placeName: 'Silver Springs',
        typeLabel: 'Spring',
      );

      final decision = brain.decide(event: event, profile: CopilotProfile.empty, memory: memory);
      expect(decision.shouldSpeak, isTrue);
    });

    test('quiet window suppresses a personality event spoken too soon after another', () {
      final brain = const CopilotBrain(baseQuietWindow: Duration(seconds: 999));
      final memory = CopilotSessionMemory();
      memory.markSpoken('previous-event');

      const event = CopilotEvent(type: CopilotEventType.arrived);
      final decision = brain.decide(event: event, profile: CopilotProfile.empty, memory: memory);
      expect(decision.shouldSpeak, isFalse);
    });

    test('a zero quiet window lets personality events speak back to back', () async {
      final brain = const CopilotBrain(baseQuietWindow: Duration.zero);
      final memory = CopilotSessionMemory();
      memory.markSpoken('previous-event');
      await Future<void>.delayed(const Duration(milliseconds: 5));

      const event = CopilotEvent(type: CopilotEventType.tripStarted, placeName: 'Ocala');
      final decision = brain.decide(event: event, profile: CopilotProfile.empty, memory: memory);
      expect(decision.shouldSpeak, isTrue);
    });

    test('a high talk-amount preference halves the effective quiet window', () async {
      final brain = const CopilotBrain(baseQuietWindow: Duration(milliseconds: 20));
      final memory = CopilotSessionMemory();
      memory.markSpoken('previous-event');
      await Future<void>.delayed(const Duration(milliseconds: 15));

      final chatty = CopilotProfile.empty.copyWith(talkAmount: InterestLevel.high);
      const event = CopilotEvent(type: CopilotEventType.tripStarted, placeName: 'Ocala');
      final decision = brain.decide(event: event, profile: chatty, memory: memory);
      expect(decision.shouldSpeak, isTrue);
    });
  });

  group('CopilotProfile', () {
    test('topicForTypeLabel maps common location types to tracked topics', () {
      expect(topicForTypeLabel('Spring'), CopilotTopic.springs);
      expect(topicForTypeLabel('Museum'), CopilotTopic.museums);
      expect(topicForTypeLabel('Restaurant'), CopilotTopic.restaurants);
      expect(topicForTypeLabel('Historic Site'), CopilotTopic.history);
      expect(topicForTypeLabel('Boat Ramp'), isNull);
    });

    test('withTopicNudged moves interest one step at a time', () {
      var profile = CopilotProfile.empty;
      expect(profile.interestIn(CopilotTopic.history), InterestLevel.medium);

      profile = profile.withTopicNudged(CopilotTopic.history, up: true);
      expect(profile.interestIn(CopilotTopic.history), InterestLevel.high);

      profile = profile.withTopicNudged(CopilotTopic.history, up: false);
      profile = profile.withTopicNudged(CopilotTopic.history, up: false);
      expect(profile.interestIn(CopilotTopic.history), InterestLevel.low);

      // Floors at low, never goes negative.
      profile = profile.withTopicNudged(CopilotTopic.history, up: false);
      expect(profile.interestIn(CopilotTopic.history), InterestLevel.low);
    });

    test('round-trips through JSON', () {
      final profile = CopilotProfile.empty
          .withTopicNudged(CopilotTopic.springs, up: true)
          .withPlaceVisited('loc-1')
          .withPlaceDiscussed('loc-2')
          .withPlaceLiked('loc-3', liked: true)
          .copyWith(sarcasm: InterestLevel.medium, talkAmount: InterestLevel.low);

      final restored = CopilotProfile.fromJson(profile.toJson());
      expect(restored.interestIn(CopilotTopic.springs), InterestLevel.high);
      expect(restored.visitedPlaceIds, {'loc-1'});
      expect(restored.discussedPlaceIds, {'loc-2'});
      expect(restored.likedPlaceIds, {'loc-3'});
      expect(restored.sarcasm, InterestLevel.medium);
      expect(restored.talkAmount, InterestLevel.low);
    });
  });
}
