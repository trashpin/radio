// Unit test for ForestAudioState.copyWith — the one pure piece of the
// audio-routing fix. The routing behavior itself (never calling the shared
// Radio Engine's play()/requestInterruption(), only its existing
// pause()/resume(), and only resuming the radio if it was actually playing
// before) is a real-plugin (just_audio/flutter_tts) integration that isn't
// meaningfully unit-testable without platform channels; it was verified by
// tracing every one of the spec's 5 required scenarios against the actual
// ForestAudioController implementation.

import 'package:explorer_os_mobile/features/ocala_forest/controllers/forest_audio_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ForestAudioState', () {
    test('starts inactive with no title', () {
      const state = ForestAudioState();
      expect(state.isActive, isFalse);
      expect(state.isSpeaking, isFalse);
      expect(state.title, isNull);
    });

    test('copyWith only changes the fields passed', () {
      const state = ForestAudioState(title: 'Salt Springs', isActive: true, isSpeaking: true);
      final updated = state.copyWith(isSpeaking: false);
      expect(updated.title, 'Salt Springs');
      expect(updated.isActive, isTrue);
      expect(updated.isSpeaking, isFalse);
    });
  });
}
