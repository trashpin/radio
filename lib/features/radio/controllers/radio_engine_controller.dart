import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_state.dart';
import 'package:explorer_os_mobile/features/radio/providers/radio_engine_providers.dart';
import 'package:explorer_os_mobile/features/radio/services/radio_engine_service.dart';

/// The UI-facing facade for the Radio Engine.
///
/// WHY THIS EXISTS: widgets should never poke at the individual services. They
/// watch this single [Notifier], which exposes the immutable [PlaybackState] and
/// forwards user/system intents (start, skip, pause/resume, interruptions) to
/// the [RadioEngineService], then republishes the fresh state so the UI rebuilds.
///
/// This is the seam a real audio adapter also uses: when its player reports a
/// track finished, it calls [completeCurrent]; the engine decides what's next
/// and this controller emits the new state.
class RadioEngineController extends Notifier<PlaybackState> {
  RadioEngineService get _engine => ref.read(radioEngineServiceProvider);

  @override
  PlaybackState build() => _engine.state;

  void _publish() => state = _engine.state;

  /// Begins playback for the already-loaded station/schedulers.
  void start() {
    _engine.start();
    _publish();
  }

  /// The audio layer reports the current segment finished; advance.
  void completeCurrent() {
    _engine.onSegmentCompleted();
    _publish();
  }

  /// Skip the current item.
  void skip() {
    _engine.skip();
    _publish();
  }

  void pause() {
    _engine.pause();
    _publish();
  }

  void resume() {
    _engine.resume();
    _publish();
  }

  /// Push a high-priority interruption (alert/announcement/GPS narration).
  void requestInterruption(AudioSegment segment) {
    _engine.requestInterruption(segment);
    _publish();
  }

  void stop() {
    _engine.stop();
    _publish();
  }
}

/// The single provider widgets watch to observe/drive Explorer Radio.
final radioEngineControllerProvider =
    NotifierProvider<RadioEngineController, PlaybackState>(
  RadioEngineController.new,
);
