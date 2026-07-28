import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/radio_director/models/radio_director_models.dart';
import 'package:explorer_os_mobile/features/radio_director/radio_director.dart';

RadioCandidate _c(RadioEventType t, {String? key, double? dist}) => RadioCandidate(
      type: t,
      id: t.name,
      title: t.name,
      triggerKey: key ?? '${t.name}:x',
      distanceMeters: dist,
    );

RadioContext _ctx({
  required List<RadioCandidate> candidates,
  bool narrationPlaying = false,
  bool musicPlaying = true,
  double sinceLast = 9999,
  RadioGuidePersonality guide = RadioGuidePersonality.explorer,
  RadioPreferences prefs = const RadioPreferences(),
  RadioPlaybackState state = RadioPlaybackState.driving,
  Set<String> played = const {},
  int? currentPriority,
}) =>
    RadioContext(
      now: DateTime(2026),
      narrationPlaying: narrationPlaying,
      musicPlaying: musicPlaying,
      secondsSinceLastNarration: sinceLast,
      candidates: candidates,
      guide: guide,
      preferences: prefs,
      playbackState: state,
      playedKeys: played,
      currentNarrationPriority: currentPriority,
    );

void main() {
  const director = RadioDirector();

  group('priority engine', () {
    test('highest priority wins', () {
      final d = director.evaluate(_ctx(candidates: [
        _c(RadioEventType.scenicView),
        _c(RadioEventType.arrival),
        _c(RadioEventType.wildlife),
      ]));
      expect(d.action, RadioAction.playNarration);
      expect(d.candidate!.type, RadioEventType.arrival);
    });

    test('music fills empty time when there are no events', () {
      final d = director.evaluate(_ctx(candidates: const []));
      expect(d.action, RadioAction.keepMusic);
      final d2 = director.evaluate(_ctx(candidates: const [], musicPlaying: false));
      expect(d2.action, RadioAction.startMusic);
    });
  });

  group('silence engine', () {
    test('non-urgent narration waits for the quiet window', () {
      // A random story right after a recent narration → suppressed (music).
      final d = director.evaluate(_ctx(
        candidates: [_c(RadioEventType.randomStory)],
        sinceLast: 30, // < 180s
      ));
      expect(d.action, RadioAction.keepMusic);
    });

    test('non-urgent narration plays once the quiet window elapses', () {
      final d = director.evaluate(_ctx(
        candidates: [_c(RadioEventType.randomStory)],
        sinceLast: 200, // > 180s
      ));
      expect(d.action, RadioAction.playNarration);
      expect(d.candidate!.type, RadioEventType.randomStory);
    });

    test('urgent triggers bypass the silence window', () {
      final d = director.evaluate(_ctx(
        candidates: [_c(RadioEventType.arrival)],
        sinceLast: 5, // very recent
      ));
      expect(d.action, RadioAction.playNarration);
      expect(d.candidate!.type, RadioEventType.arrival);
    });
  });

  group('no stacking / interrupts', () {
    test('does not stack a low-priority narration over a playing one', () {
      final d = director.evaluate(_ctx(
        candidates: [_c(RadioEventType.randomStory)],
        narrationPlaying: true,
        currentPriority: 40,
      ));
      expect(d.action, RadioAction.keepCurrent);
    });

    test('safety interrupts an in-progress lower-priority narration', () {
      final d = director.evaluate(_ctx(
        candidates: [_c(RadioEventType.safety)],
        narrationPlaying: true,
        currentPriority: 40,
      ));
      expect(d.action, RadioAction.playNarration);
      expect(d.candidate!.type, RadioEventType.safety);
    });
  });

  group('anti-repeat', () {
    test('never replays an already-played trigger this visit', () {
      final d = director.evaluate(_ctx(
        candidates: [_c(RadioEventType.arrival, key: 'arrival:silver')],
        played: {'arrival:silver'},
      ));
      expect(d.action, RadioAction.keepMusic);
    });
  });

  group('guide personalities', () {
    test('naturalist favors wildlife over an equal-tier historic site', () {
      final d = director.evaluate(_ctx(
        candidates: [
          _c(RadioEventType.wildlife),
          _c(RadioEventType.historicSite),
        ],
        guide: RadioGuidePersonality.naturalist,
        sinceLast: 500,
      ));
      expect(d.candidate!.type, RadioEventType.wildlife);
    });

    test('road trip damps extras so music dominates', () {
      // A scenic view under Road Trip, just outside quiet → still gated because
      // its damped score stays non-urgent and quiet not yet elapsed.
      final d = director.evaluate(_ctx(
        candidates: [_c(RadioEventType.scenicView)],
        guide: RadioGuidePersonality.roadTrip,
        sinceLast: 60,
      ));
      expect(d.action, RadioAction.keepMusic);
    });
  });

  group('preferences', () {
    test('narration at 0% mutes extras but not safety triggers', () {
      const silent = RadioPreferences(narrationPercent: 0);
      final story = director.evaluate(_ctx(
        candidates: [_c(RadioEventType.randomStory)],
        prefs: silent,
        sinceLast: 999,
      ));
      expect(story.action, RadioAction.keepMusic);

      final safety = director.evaluate(_ctx(
        candidates: [_c(RadioEventType.safety)],
        prefs: silent,
      ));
      expect(safety.action, RadioAction.playNarration);
    });

    test('story frequency off removes random stories', () {
      const noStories = RadioPreferences(storyFrequency: RadioFrequency.off);
      final d = director.evaluate(_ctx(
        candidates: [_c(RadioEventType.randomStory)],
        prefs: noStories,
        sinceLast: 999,
      ));
      expect(d.action, RadioAction.keepMusic);
    });
  });

  group('playback state', () {
    test('being stopped shortens the quiet window (more narration allowed)', () {
      // 100s since last: gated while driving (needs 180), allowed when stopped
      // (needs 90).
      final driving = director.evaluate(_ctx(
        candidates: [_c(RadioEventType.interestingFact)],
        sinceLast: 100,
        state: RadioPlaybackState.driving,
      ));
      expect(driving.action, RadioAction.keepMusic);

      final stopped = director.evaluate(_ctx(
        candidates: [_c(RadioEventType.interestingFact)],
        sinceLast: 100,
        state: RadioPlaybackState.stopped,
      ));
      expect(stopped.action, RadioAction.playNarration);
    });
  });
}
