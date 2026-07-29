import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:explorer_os_mobile/features/location_intelligence/data/location_content_repository.dart';
import 'package:explorer_os_mobile/features/locations/data/location_narration.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';
import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/events/radio_event.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_state.dart';
import 'package:explorer_os_mobile/features/radio/providers/radio_engine_providers.dart';

/// State of the "What's right here?" nearby-location narration.
class NearbyNarrationState {
  const NearbyNarrationState({this.location, this.narrating = false, this.message});
  final MasterLocation? location;
  final bool narrating;
  final String? message;
  bool get active => location != null;
}

/// Powers "I See Something → What's right here?": queries the ONE master
/// Location database for the nearest location and narrates it — playing its
/// recorded audio through the radio engine's interruption path when available,
/// otherwise speaking a composed script via on-device TTS.
class NearbyNarrationController extends Notifier<NearbyNarrationState> {
  final FlutterTts _tts = FlutterTts();
  bool _wired = false;
  bool _wasPlaying = false;
  String? _segId;
  Timer? _fallback;
  StreamSubscription<RadioEvent>? _events;

  @override
  NearbyNarrationState build() => const NearbyNarrationState();

  void _wire() {
    if (_wired) return;
    _wired = true;
    _tts.setCompletionHandler(_finishTts);
    _tts.setErrorHandler((_) => _finishTts());
    _events = ref.read(radioEngineServiceProvider).events.listen((e) {
      if (_segId != null && e is SegmentCompleted && e.segment.id == _segId) {
        _segId = null;
        if (state.location != null) {
          state = NearbyNarrationState(location: state.location);
        }
      }
    });
    ref.onDispose(() {
      _events?.cancel();
      _fallback?.cancel();
    });
  }

  /// Find and narrate the nearest master location to the current GPS position.
  Future<void> narrateNearest() async {
    _wire();
    _fallback?.cancel();

    final center = ref.read(mapCenterProvider);
    if (center == null) {
      state = const NearbyNarrationState(
          message: 'Location unknown — enable GPS to hear what\'s around you.');
      return;
    }
    final all = ref.read(masterLocationsProvider).value ?? const [];
    final top = ref
        .read(locationEngineProvider)
        .topNearby(center.latitude, center.longitude, all);
    if (top == null) {
      state = const NearbyNarrationState(
          message: 'Nothing nearby yet — keep exploring.');
      return;
    }

    final content = ref.read(locationContentItemsProvider);
    final narration = resolveLocationNarration(top.location, content);
    state = NearbyNarrationState(location: top.location, narrating: true);

    if (narration.hasAudio) {
      _segId = 'near:${top.location.id}:${DateTime.now().millisecondsSinceEpoch}';
      ref.read(radioEngineControllerProvider.notifier).requestInterruption(
            AudioSegment(
              id: _segId!,
              title: narration.title,
              artist: top.location.type.label,
              type: AudioSegmentType.narration,
              priority: PlaybackPriority.scheduledAnnouncement,
              audioUrl: narration.audioUrl!,
              interruptible: true,
              resumeAfter: true,
            ),
          );
    } else {
      await _speak(narration.text);
    }
  }

  Future<void> _speak(String script) async {
    final controller = ref.read(radioEngineControllerProvider.notifier);
    _wasPlaying = ref.read(radioEngineControllerProvider).status ==
        PlaybackStatus.playing;
    if (_wasPlaying) controller.pause();
    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSpeechRate(0.45);
      await _tts.setPitch(1.0);
    } catch (_) {}
    final secs = (script.split(RegExp(r'\s+')).length / 2.6).round().clamp(15, 180);
    _fallback = Timer(Duration(seconds: secs + 6), _finishTts);
    try {
      await _tts.speak(script);
    } catch (_) {
      _finishTts();
    }
  }

  void _finishTts() {
    _fallback?.cancel();
    _fallback = null;
    if (_wasPlaying) {
      try {
        ref.read(radioEngineControllerProvider.notifier).resume();
      } catch (_) {}
      _wasPlaying = false;
    }
    if (state.location != null) {
      state = NearbyNarrationState(location: state.location);
    }
  }

  Future<void> clear() async {
    if (_segId != null) {
      _segId = null;
      try {
        ref.read(radioEngineControllerProvider.notifier).skip();
      } catch (_) {}
    } else {
      try {
        await _tts.stop();
      } catch (_) {}
      _finishTts();
    }
    state = const NearbyNarrationState();
  }
}

final nearbyNarrationControllerProvider =
    NotifierProvider<NearbyNarrationController, NearbyNarrationState>(
        NearbyNarrationController.new);
