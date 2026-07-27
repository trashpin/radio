import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_output.dart';
import 'playback_manager.dart';
import 'playback_models.dart';

/// The app-wide [PlaybackManager] — the single audio engine every feature calls
/// into. Backed by two real `just_audio` outputs (music + narration channels).
final playbackManagerProvider = Provider<PlaybackManager>((ref) {
  final manager = PlaybackManager(
    musicOutput: JustAudioOutput(),
    narrationOutput: JustAudioOutput(),
  );
  ref.onDispose(manager.dispose);
  return manager;
});

/// A live stream of the engine's [PlaybackSnapshot] for UI / the debug panel.
final playbackSnapshotProvider = StreamProvider<PlaybackSnapshot>((ref) {
  final manager = ref.watch(playbackManagerProvider);
  return manager.snapshots;
});

/// A live stream of the engine's emitted [PlaybackEvent]s.
final playbackEventProvider = StreamProvider<PlaybackEvent>((ref) {
  final manager = ref.watch(playbackManagerProvider);
  return manager.events;
});
