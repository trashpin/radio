import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/around_me/models/experience.dart';
import 'package:explorer_os_mobile/features/around_me/providers/around_me_providers.dart';
import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_enums.dart';
import 'package:explorer_os_mobile/features/playback/playback_manager.dart';
import 'package:explorer_os_mobile/features/playback/playback_models.dart';
import 'package:explorer_os_mobile/features/playback/playback_providers.dart';
import 'package:explorer_os_mobile/features/radio_director/models/radio_director_models.dart';
import 'package:explorer_os_mobile/features/radio_director/radio_director.dart';

// --- Config / guide / preferences providers (admin + user tunable) ----------

final radioDirectorConfigProvider =
    NotifierProvider<RadioDirectorConfigNotifier, RadioDirectorConfig>(
        RadioDirectorConfigNotifier.new);

class RadioDirectorConfigNotifier extends Notifier<RadioDirectorConfig> {
  @override
  RadioDirectorConfig build() => const RadioDirectorConfig();
  void set(RadioDirectorConfig c) => state = c;
}

final radioGuideProvider =
    NotifierProvider<RadioGuideNotifier, RadioGuidePersonality>(
        RadioGuideNotifier.new);

class RadioGuideNotifier extends Notifier<RadioGuidePersonality> {
  @override
  RadioGuidePersonality build() => RadioGuidePersonality.explorer;
  void set(RadioGuidePersonality g) => state = g;
}

final radioPreferencesProvider =
    NotifierProvider<RadioPreferencesNotifier, RadioPreferences>(
        RadioPreferencesNotifier.new);

class RadioPreferencesNotifier extends Notifier<RadioPreferences> {
  @override
  RadioPreferences build() => const RadioPreferences();
  void set(RadioPreferences p) => state = p;
}

final radioDirectorProvider = Provider<RadioDirector>((ref) =>
    RadioDirector(config: ref.watch(radioDirectorConfigProvider)));

// --- Runtime snapshot -------------------------------------------------------

class RadioDirectorSnapshot {
  const RadioDirectorSnapshot({
    this.running = false,
    this.conversationOpen = false,
    this.lastDecision,
    this.decisionLog = const [],
    this.playedCount = 0,
    this.currentNarration,
    this.secondsSinceLastNarration = 0,
    this.musicStatus = ChannelStatus.idle,
    this.narrationStatus = ChannelStatus.idle,
  });

  final bool running;
  final bool conversationOpen;
  final RadioDecision? lastDecision;
  final List<String> decisionLog;
  final int playedCount;
  final String? currentNarration;
  final double secondsSinceLastNarration;
  final ChannelStatus musicStatus;
  final ChannelStatus narrationStatus;

  RadioDirectorSnapshot copyWith({
    bool? running,
    bool? conversationOpen,
    RadioDecision? lastDecision,
    List<String>? decisionLog,
    int? playedCount,
    String? currentNarration,
    double? secondsSinceLastNarration,
    ChannelStatus? musicStatus,
    ChannelStatus? narrationStatus,
  }) =>
      RadioDirectorSnapshot(
        running: running ?? this.running,
        conversationOpen: conversationOpen ?? this.conversationOpen,
        lastDecision: lastDecision ?? this.lastDecision,
        decisionLog: decisionLog ?? this.decisionLog,
        playedCount: playedCount ?? this.playedCount,
        currentNarration: currentNarration ?? this.currentNarration,
        secondsSinceLastNarration:
            secondsSinceLastNarration ?? this.secondsSinceLastNarration,
        musicStatus: musicStatus ?? this.musicStatus,
        narrationStatus: narrationStatus ?? this.narrationStatus,
      );
}

/// The always-on Radio Director runtime.
///
/// While [running], it ticks every few seconds, builds a [RadioContext] from
/// the live GPS + Around Me state, asks the [RadioDirector] what to play, and
/// enacts the decision through the [PlaybackManager] (music fills gaps;
/// narration ducks music and resumes). The visitor only ever uses: Play/Pause,
/// Skip, I See Something, What's Around Me.
final radioDirectorControllerProvider =
    NotifierProvider<RadioDirectorController, RadioDirectorSnapshot>(
        RadioDirectorController.new);

class RadioDirectorController extends Notifier<RadioDirectorSnapshot> {
  Timer? _ticker;
  DateTime? _lastNarrationAt;
  int? _currentNarrationPriority;
  final Set<String> _playedKeys = {};
  final List<String> _log = [];
  StreamSubscription<PlaybackEvent>? _pbSub;

  /// Demo audio (the debug panel injects tones; production injects a real
  /// playlist + per-POI narration URLs).
  String? musicUrl;
  String? narrationFallbackUrl;

  PlaybackManager get _pm => ref.read(playbackManagerProvider);

  @override
  RadioDirectorSnapshot build() {
    ref.onDispose(() {
      _ticker?.cancel();
      _pbSub?.cancel();
    });
    // When a narration finishes, remember the time so the silence window starts.
    _pbSub = _pm.events.listen((e) {
      if (e.type == PlaybackEventType.narrationFinished) {
        _lastNarrationAt = DateTime.now();
        _currentNarrationPriority = null;
      }
    });
    return const RadioDirectorSnapshot();
  }

  // --- The four controls ---------------------------------------------------

  /// Play/Pause the radio.
  Future<void> togglePlay() => state.running ? stop() : start();

  Future<void> start() async {
    if (state.running) return;
    _lastNarrationAt ??= DateTime.now().subtract(const Duration(minutes: 5));
    state = state.copyWith(running: true);
    // Kick music immediately so there's never dead air.
    await _ensureMusic();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 3), (_) => _tick());
    _tick();
  }

  Future<void> stop() async {
    _ticker?.cancel();
    _ticker = null;
    await _pm.pauseMusic();
    await _pm.cancelNarration();
    state = state.copyWith(running: false);
  }

  /// Skip the current narration: fade it out, resume music, and never replay it
  /// this visit.
  Future<void> skip() async {
    final current = _pm.getCurrentTrack();
    if (current != null) {
      final key = current.metadata['triggerKey'];
      if (key is String) _playedKeys.add(key);
    }
    await _pm.cancelNarration();
    _lastNarrationAt = DateTime.now();
    _currentNarrationPriority = null;
    _appendLog('⏭ skipped narration');
  }

  /// "I See Something" — pause the radio, open a live AI conversation using the
  /// nearby context, then resume exactly where it stopped.
  Future<void> openISeeSomething() => _openConversation('I See Something');

  /// "What's Around Me" — pause the radio, summarize nearby attractions, resume.
  Future<void> openWhatsAroundMe() => _openConversation("What's Around Me");

  Future<void> _openConversation(String label) async {
    _ticker?.cancel();
    _ticker = null;
    await _pm.pauseMusic();
    await _pm.cancelNarration();
    state = state.copyWith(conversationOpen: true, running: false);
    _appendLog('🎙 $label — radio paused');
  }

  /// Called when the conversation modal closes — resume the radio.
  Future<void> resumeFromConversation() async {
    state = state.copyWith(conversationOpen: false);
    _appendLog('▶ resumed radio');
    await start();
  }

  // --- The tick ------------------------------------------------------------

  void _tick() {
    if (!state.running) return;
    final director = ref.read(radioDirectorProvider);
    final ctx = _buildContext(director.config);
    final decision = director.evaluate(ctx);
    _enact(decision);
  }

  RadioContext _buildContext(RadioDirectorConfig config) {
    final gps = ref.read(gpsControllerProvider);
    final experiences = ref.read(aroundMeExperiencesProvider);
    final snap = _pm.snapshot;

    final candidates = <RadioCandidate>[];
    // Nearby experiences → typed candidates within trigger range.
    for (final e in experiences) {
      if (e.distanceMeters > config.gpsTriggerDistanceMeters) continue;
      candidates.add(RadioCandidate(
        type: _eventTypeFor(e),
        id: e.id,
        title: e.name,
        triggerKey: 'poi:${e.id}',
        audioUrl: (e.audioUrl ?? '').isNotEmpty ? e.audioUrl : narrationFallbackUrl,
        distanceMeters: e.distanceMeters,
      ));
    }
    // GPS arrival trigger: the nearest experience within ~120 m.
    if (experiences.isNotEmpty) {
      final nearest = experiences.first;
      if (nearest.distanceMeters <= 120) {
        candidates.add(RadioCandidate(
          type: RadioEventType.arrival,
          id: nearest.id,
          title: 'Arriving at ${nearest.name}',
          triggerKey: 'arrival:${nearest.id}',
          audioUrl: narrationFallbackUrl,
          distanceMeters: nearest.distanceMeters,
        ));
      }
    }

    return RadioContext(
      now: DateTime.now(),
      narrationPlaying: snap.narrationStatus == ChannelStatus.playing,
      musicPlaying: snap.musicStatus == ChannelStatus.playing,
      secondsSinceLastNarration: _lastNarrationAt == null
          ? 9999
          : DateTime.now().difference(_lastNarrationAt!).inSeconds.toDouble(),
      candidates: candidates,
      guide: ref.read(radioGuideProvider),
      preferences: ref.read(radioPreferencesProvider),
      playbackState: _playbackStateFor(gps.movementState, gps.travelMode),
      playedKeys: _playedKeys,
      currentNarrationPriority: _currentNarrationPriority,
    );
  }

  Future<void> _enact(RadioDecision d) async {
    switch (d.action) {
      case RadioAction.playNarration:
        final c = d.candidate!;
        _playedKeys.add(c.triggerKey);
        _lastNarrationAt = DateTime.now();
        _currentNarrationPriority = d.score.round();
        if ((c.audioUrl ?? '').isNotEmpty) {
          await _pm.playNarration(PlaybackItem(
            type: _playbackTypeFor(c.type),
            title: c.title,
            audioUrl: c.audioUrl!,
            metadata: {'triggerKey': c.triggerKey, 'eventType': c.type.name},
          ));
        }
        _appendLog('▶ ${d.toString()}');
      case RadioAction.startMusic:
        await _ensureMusic();
        _appendLog('♪ ${d.toString()}');
      case RadioAction.keepMusic:
      case RadioAction.keepCurrent:
        break;
    }
    _publish(d);
  }

  Future<void> _ensureMusic() async {
    if ((musicUrl ?? '').isEmpty) return;
    final snap = _pm.snapshot;
    if (snap.musicStatus != ChannelStatus.playing &&
        snap.narrationStatus != ChannelStatus.playing) {
      await _pm.playMusic(PlaybackItem(
          type: PlaybackItemType.music, title: 'Station', audioUrl: musicUrl!));
    }
  }

  void _appendLog(String line) {
    final t = DateTime.now().toIso8601String().substring(11, 19);
    _log.insert(0, '$t  $line');
    if (_log.length > 40) _log.removeLast();
  }

  void _publish(RadioDecision d) {
    final snap = _pm.snapshot;
    state = state.copyWith(
      lastDecision: d,
      decisionLog: List.unmodifiable(_log),
      playedCount: _playedKeys.length,
      currentNarration: snap.narrationTrack?.title,
      secondsSinceLastNarration: _lastNarrationAt == null
          ? 9999
          : DateTime.now().difference(_lastNarrationAt!).inSeconds.toDouble(),
      musicStatus: snap.musicStatus,
      narrationStatus: snap.narrationStatus,
    );
  }

  // --- Mappings ------------------------------------------------------------

  RadioEventType _eventTypeFor(Experience e) {
    final c = e.category.toLowerCase();
    if (c.contains('safety') || c.contains('alert')) return RadioEventType.safety;
    if (c.contains('bird') ||
        c.contains('wildlife') ||
        c.contains('mammal') ||
        c.contains('reptile') ||
        c.contains('fish') ||
        c.contains('amphib')) {
      return RadioEventType.wildlife;
    }
    if (c.contains('historic') || c.contains('history')) {
      return RadioEventType.historicSite;
    }
    if (c.contains('scenic') || c.contains('overlook')) {
      return RadioEventType.scenicView;
    }
    if (c.contains('spring') || c.contains('waterfall') || c.contains('gem')) {
      return RadioEventType.hiddenGem;
    }
    if (e.isTrail) return RadioEventType.hiddenGem;
    return RadioEventType.interestingFact;
  }

  PlaybackItemType _playbackTypeFor(RadioEventType t) {
    switch (t) {
      case RadioEventType.arrival:
        return PlaybackItemType.arrival;
      case RadioEventType.departure:
        return PlaybackItemType.departure;
      case RadioEventType.safety:
        return PlaybackItemType.safety;
      case RadioEventType.approach:
        return PlaybackItemType.arrival;
      default:
        return PlaybackItemType.poi;
    }
  }

  RadioPlaybackState _playbackStateFor(MovementState m, TravelMode mode) {
    if (m != MovementState.moving) return RadioPlaybackState.stopped;
    if (mode == TravelMode.walking) return RadioPlaybackState.walking;
    return RadioPlaybackState.driving;
  }
}
