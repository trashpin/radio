import 'dart:async';

import 'package:flutter/foundation.dart';

import 'audio_output.dart';
import 'playback_models.dart';

/// The central audio controller for ExplorerOS.
///
/// This is the SINGLE source of truth for all music and narration playback.
/// Every other system (GPS, Explorer Radio, Narration, AI Guide, "I See
/// Something", Safety Alerts, POIs, the Music Player) is expected to send
/// requests here and NEVER touch the audio players directly.
///
/// Design:
/// - Two independent [AudioOutput] channels: one for music, one for
///   narration/announcements. This lets music be ducked (faded + paused) while
///   a narration plays on its own channel and then smoothly resumed.
/// - A priority-ordered narration queue. Higher-priority items interrupt
///   lower-priority ones; an interrupted narration is re-queued to resume.
/// - Explicit, mutually-exclusive [PlaybackState] and per-channel
///   [ChannelStatus].
/// - Events on [events] and rich [snapshots] for UI / the debug panel.
///
/// Phase 1 intentionally has NO knowledge of GPS, AI, destinations, routes, or
/// Explorer Radio logic — it is a reusable engine those systems will call into.
class PlaybackManager {
  PlaybackManager({
    required AudioOutput musicOutput,
    required AudioOutput narrationOutput,
    this.fadeDuration = const Duration(seconds: 1),
    this.fadeSteps = 16,
    void Function(Object error, StackTrace stack)? onError,
  })  : _music = musicOutput,
        _narration = narrationOutput,
        _logError = onError ?? _defaultLog {
    _musicCompleteSub = _music.completions.listen((_) => _onMusicComplete());
    _narrationCompleteSub =
        _narration.completions.listen((_) => _onNarrationComplete());
  }

  final AudioOutput _music;
  final AudioOutput _narration;

  /// How long music fades take when ducking/resuming around a narration.
  final Duration fadeDuration;

  /// Number of volume steps used to approximate a smooth fade.
  final int fadeSteps;

  final void Function(Object error, StackTrace stack) _logError;

  late final StreamSubscription<void> _musicCompleteSub;
  late final StreamSubscription<void> _narrationCompleteSub;

  final StreamController<PlaybackEvent> _events =
      StreamController<PlaybackEvent>.broadcast();
  late final StreamController<PlaybackSnapshot> _snapshots =
      StreamController<PlaybackSnapshot>.broadcast(
    onListen: () {
      // Seed new listeners with the current snapshot so the UI has a value
      // immediately (broadcast streams otherwise only deliver future events).
      if (!_disposed) _snapshots.add(_buildSnapshot());
    },
  );

  PlaybackState _state = PlaybackState.idle;
  ChannelStatus _musicStatus = ChannelStatus.idle;
  ChannelStatus _narrationStatus = ChannelStatus.idle;

  double _volume = 1.0;
  bool _muted = false;

  // Music playlist + cursor.
  List<PlaybackItem> _playlist = [];
  int _index = -1;
  PlaybackItem? _currentMusic;
  bool _musicLoaded = false; // has the music channel actually loaded a source

  // Narration channel.
  final List<PlaybackItem> _queue = [];
  PlaybackItem? _currentNarration;
  PlaybackItem? _lastNarration; // for replay()
  bool _resumeMusicAfterNarration = false;

  PlaybackEvent? _lastEvent;
  bool _disposed = false;

  double get _effectiveMusicVolume => _muted ? 0.0 : _volume;
  double get _effectiveNarrationVolume => _muted ? 0.0 : 1.0;

  // ---------------------------------------------------------------------------
  // Public observation
  // ---------------------------------------------------------------------------

  Stream<PlaybackEvent> get events => _events.stream;
  Stream<PlaybackSnapshot> get snapshots => _snapshots.stream;

  PlaybackState getCurrentState() => _state;

  /// The audible "now playing" item — narration takes precedence over music.
  PlaybackItem? getCurrentTrack() => _currentNarration ?? _currentMusic;

  PlaybackSnapshot get snapshot => _buildSnapshot();

  double get volume => _volume;
  bool get muted => _muted;
  int get queueLength => _queue.length;
  List<PlaybackItem> get queue => List.unmodifiable(_queue);

  // ---------------------------------------------------------------------------
  // Music controls
  // ---------------------------------------------------------------------------

  /// Play [item] as music. Optionally provide the [playlist] it belongs to so
  /// [next]/[previous]/[skip] can navigate. If a narration is currently
  /// playing, the track is selected and starts automatically once narration
  /// finishes.
  Future<void> playMusic(PlaybackItem item, {List<PlaybackItem>? playlist}) async {
    if (_disposed) return;
    if (playlist != null && playlist.isNotEmpty) {
      _playlist = List.of(playlist);
      _index = _playlist.indexWhere((e) => e.id == item.id);
      if (_index < 0) {
        _playlist.insert(0, item);
        _index = 0;
      }
    } else {
      _playlist = [item];
      _index = 0;
    }
    await _startCurrentMusic();
  }

  Future<void> pauseMusic() async {
    if (_disposed) return;
    if (_musicStatus != ChannelStatus.playing) return;
    await _music.pause();
    _musicStatus = ChannelStatus.paused;
    if (_state == PlaybackState.playingMusic) _setState(PlaybackState.paused);
    _emit(PlaybackEventType.playbackPaused, item: _currentMusic);
  }

  Future<void> resumeMusic() async {
    if (_disposed || _currentMusic == null) return;
    // Don't fight a narration; music will resume when it ends.
    if (_currentNarration != null) {
      _resumeMusicAfterNarration = true;
      _pushSnapshot();
      return;
    }
    if (!_musicLoaded) {
      await _startCurrentMusic();
      return;
    }
    await _music.setVolume(_effectiveMusicVolume);
    await _music.resume();
    _musicStatus = ChannelStatus.playing;
    _setState(PlaybackState.playingMusic);
    _emit(PlaybackEventType.playbackStarted, item: _currentMusic);
  }

  Future<void> stopMusic() async {
    if (_disposed) return;
    await _music.stop();
    _musicStatus = ChannelStatus.stopped;
    _musicLoaded = false;
    final was = _currentMusic;
    _currentMusic = null;
    _resumeMusicAfterNarration = false;
    if (_currentNarration == null) {
      _setState(PlaybackState.stopped);
    }
    _emit(PlaybackEventType.playbackStopped, item: was);
  }

  /// Advance to the next track in the playlist (alias: [skip]).
  Future<void> next() async {
    if (_disposed || _playlist.isEmpty) return;
    if (_index < _playlist.length - 1) {
      _index++;
      await _startCurrentMusic();
    } else {
      await stopMusic();
    }
  }

  Future<void> skip() => next();

  /// Go back one track (or restart the current one if at the start).
  Future<void> previous() async {
    if (_disposed || _playlist.isEmpty) return;
    if (_index > 0) _index--;
    await _startCurrentMusic();
  }

  Future<void> setVolume(double value) async {
    if (_disposed) return;
    _volume = value.clamp(0.0, 1.0);
    if (_currentNarration == null && _musicStatus == ChannelStatus.playing) {
      await _music.setVolume(_effectiveMusicVolume);
    }
    _pushSnapshot();
  }

  Future<void> setMuted(bool value) async {
    if (_disposed) return;
    _muted = value;
    if (_currentNarration != null) {
      await _narration.setVolume(_effectiveNarrationVolume);
    } else if (_musicStatus == ChannelStatus.playing) {
      await _music.setVolume(_effectiveMusicVolume);
    }
    _pushSnapshot();
  }

  Future<void> toggleMute() => setMuted(!_muted);

  /// Crossfade the currently-playing music into [next]: fade the current track
  /// out, switch source, then fade the new track in.
  Future<void> crossfade(PlaybackItem next) async {
    if (_disposed) return;
    if (_currentNarration != null) {
      // Can't crossfade audibly under a narration; just select it to start
      // once narration ends.
      await playMusic(next);
      return;
    }
    if (_musicStatus == ChannelStatus.playing) {
      await _fade(_music, _effectiveMusicVolume, 0.0);
    }
    _playlist = [next];
    _index = 0;
    final track = next.copyWith(status: PlaybackItemStatus.playing);
    _playlist[0] = track;
    _currentMusic = track;
    try {
      await _music.setVolume(0.0);
      await _music.play(track.audioUrl);
      _musicLoaded = true;
      _musicStatus = ChannelStatus.playing;
      _setState(PlaybackState.playingMusic);
      _emit(PlaybackEventType.musicStarted, item: track);
      _emit(PlaybackEventType.playbackStarted, item: track);
      await _fade(_music, 0.0, _effectiveMusicVolume);
    } catch (e, st) {
      _handlePlaybackError(track, e, st, isMusic: true);
    }
  }

  /// Fade the music channel out (does not change state/queue).
  Future<void> fadeOut() async {
    if (_disposed) return;
    if (_musicStatus == ChannelStatus.playing) {
      await _fade(_music, _effectiveMusicVolume, 0.0);
    }
  }

  /// Fade the music channel in to the current volume.
  Future<void> fadeIn() async {
    if (_disposed) return;
    if (_musicStatus == ChannelStatus.playing) {
      await _fade(_music, 0.0, _effectiveMusicVolume);
    }
  }

  // ---------------------------------------------------------------------------
  // Narration controls
  // ---------------------------------------------------------------------------

  /// Request that [item] play. It enters the priority queue and plays now if it
  /// outranks whatever is currently on the narration channel (or if the channel
  /// is free). Music is ducked automatically.
  Future<void> playNarration(PlaybackItem item) async {
    if (_disposed) return;
    _enqueue(item);
    await _processQueue();
  }

  /// Add [item] to the narration queue (plays in priority order).
  Future<void> queueNarration(PlaybackItem item) async {
    if (_disposed) return;
    _enqueue(item);
    await _processQueue();
  }

  /// Replay the most recently played (or currently playing) narration.
  Future<void> replayNarration() async {
    if (_disposed) return;
    final last = _currentNarration ?? _lastNarration;
    if (last == null) return;
    await playNarration(last.copyWith(status: PlaybackItemStatus.queued));
  }

  Future<void> pauseNarration() async {
    if (_disposed) return;
    if (_narrationStatus != ChannelStatus.playing) return;
    await _narration.pause();
    _narrationStatus = ChannelStatus.paused;
    _setState(PlaybackState.paused);
    _emit(PlaybackEventType.playbackPaused, item: _currentNarration);
  }

  Future<void> resumeNarration() async {
    if (_disposed) return;
    if (_currentNarration == null ||
        _narrationStatus != ChannelStatus.paused) {
      return;
    }
    await _narration.resume();
    _narrationStatus = ChannelStatus.playing;
    _setState(PlaybackState.playingNarration);
    _emit(PlaybackEventType.playbackStarted, item: _currentNarration);
  }

  /// Stop the current narration and move on (next queued narration, else resume
  /// music).
  Future<void> cancelNarration() async {
    if (_disposed) return;
    if (_currentNarration == null) return;
    await _narration.stop();
    final was = _currentNarration!.copyWith(status: PlaybackItemStatus.cancelled);
    _currentNarration = null;
    _narrationStatus = ChannelStatus.stopped;
    _emit(PlaybackEventType.playbackStopped, item: was);
    if (_queue.isNotEmpty) {
      await _startNarration(_queue.removeAt(0));
    } else {
      await _resumeOrStartMusic();
    }
  }

  /// Empty the pending narration queue (does not stop the current narration).
  Future<void> clearQueue() async {
    if (_disposed) return;
    _queue.clear();
    _emit(PlaybackEventType.queueUpdated);
  }

  // ---------------------------------------------------------------------------
  // Internal: music
  // ---------------------------------------------------------------------------

  Future<void> _startCurrentMusic() async {
    if (_index < 0 || _index >= _playlist.length) {
      await stopMusic();
      return;
    }
    final track = _playlist[_index].copyWith(status: PlaybackItemStatus.playing);
    _playlist[_index] = track;
    _currentMusic = track;

    // Defer audible playback while a narration owns the channel; it will start
    // when narration finishes (via _resumeOrStartMusic).
    if (_currentNarration != null) {
      _resumeMusicAfterNarration = true;
      _musicLoaded = false;
      _musicStatus = ChannelStatus.paused;
      _pushSnapshot();
      return;
    }

    try {
      await _music.setVolume(_effectiveMusicVolume);
      await _music.play(track.audioUrl);
      _musicLoaded = true;
      _musicStatus = ChannelStatus.playing;
      _setState(PlaybackState.playingMusic);
      _emit(PlaybackEventType.musicStarted, item: track);
      _emit(PlaybackEventType.playbackStarted, item: track);
    } catch (e, st) {
      _handlePlaybackError(track, e, st, isMusic: true);
    }
  }

  void _onMusicComplete() {
    if (_disposed) return;
    final finished = _currentMusic;
    if (finished != null) {
      _emit(PlaybackEventType.playbackFinished, item: finished);
    }
    // Auto-advance the playlist.
    if (_index < _playlist.length - 1) {
      _index++;
      unawaited(_startCurrentMusic());
    } else {
      _musicStatus = ChannelStatus.stopped;
      _musicLoaded = false;
      _currentMusic = null;
      if (_currentNarration == null) _setState(PlaybackState.idle);
      _pushSnapshot();
    }
  }

  // ---------------------------------------------------------------------------
  // Internal: narration queue
  // ---------------------------------------------------------------------------

  void _enqueue(PlaybackItem item) {
    final it = item.copyWith(status: PlaybackItemStatus.queued);
    // Insert maintaining priority descending, FIFO within equal priority.
    var i = 0;
    while (i < _queue.length && _queue[i].priority >= it.priority) {
      i++;
    }
    _queue.insert(i, it);
    _emit(PlaybackEventType.queueUpdated, item: it);
  }

  Future<void> _processQueue() async {
    if (_disposed) return;

    // A narration is currently playing.
    if (_currentNarration != null &&
        _narrationStatus == ChannelStatus.playing) {
      final canInterrupt = _queue.isNotEmpty &&
          _queue.first.priority > _currentNarration!.priority;
      if (!canInterrupt) return; // let the current one finish
      // Re-queue the interrupted narration so it resumes after the higher one.
      final interrupted =
          _currentNarration!.copyWith(status: PlaybackItemStatus.queued);
      await _narration.stop();
      _currentNarration = null;
      _narrationStatus = ChannelStatus.stopped;
      _enqueue(interrupted);
      // fall through to start the highest-priority item
    }

    if (_currentNarration != null) return; // paused narration owns the channel
    if (_queue.isEmpty) return;
    await _startNarration(_queue.removeAt(0));
  }

  Future<void> _startNarration(PlaybackItem item) async {
    final playing = item.copyWith(status: PlaybackItemStatus.playing);
    _currentNarration = playing;

    // Duck music if it's playing.
    if (_musicStatus == ChannelStatus.playing) {
      _resumeMusicAfterNarration = true;
      await _fade(_music, _effectiveMusicVolume, 0.0);
      await _music.pause();
      _musicStatus = ChannelStatus.paused;
    }

    try {
      await _narration.setVolume(_effectiveNarrationVolume);
      await _narration.play(playing.audioUrl);
      _narrationStatus = ChannelStatus.playing;
      _setState(PlaybackState.playingNarration);
      _emit(PlaybackEventType.narrationStarted, item: playing);
      _emit(PlaybackEventType.playbackStarted, item: playing);
    } catch (e, st) {
      _handlePlaybackError(playing, e, st, isMusic: false);
    }
  }

  void _onNarrationComplete() {
    if (_disposed) return;
    final finished = _currentNarration;
    _currentNarration = null;
    _narrationStatus = ChannelStatus.idle;
    if (finished != null) {
      _lastNarration = finished.copyWith(status: PlaybackItemStatus.finished);
      _emit(PlaybackEventType.narrationFinished, item: _lastNarration);
      _emit(PlaybackEventType.playbackFinished, item: _lastNarration);
    }
    if (_queue.isNotEmpty) {
      unawaited(_startNarration(_queue.removeAt(0)));
      return;
    }
    unawaited(_resumeOrStartMusic());
  }

  /// After the narration channel goes quiet, bring music back: resume the
  /// ducked track (fading in), or start the selected-but-deferred track, or go
  /// idle if there is no music.
  Future<void> _resumeOrStartMusic() async {
    final shouldResume = _resumeMusicAfterNarration;
    _resumeMusicAfterNarration = false;
    if (!shouldResume || _currentMusic == null) {
      _setState(_currentMusic != null ? PlaybackState.paused : PlaybackState.idle);
      _pushSnapshot();
      return;
    }
    if (_musicLoaded) {
      try {
        await _music.setVolume(0.0);
        await _music.resume();
        _musicStatus = ChannelStatus.playing;
        _setState(PlaybackState.playingMusic);
        _emit(PlaybackEventType.musicStarted, item: _currentMusic);
        await _fade(_music, 0.0, _effectiveMusicVolume);
      } catch (e, st) {
        _handlePlaybackError(_currentMusic!, e, st, isMusic: true);
      }
    } else {
      // Selected during narration but never loaded — start it fresh now.
      await _startCurrentMusic();
    }
  }

  // ---------------------------------------------------------------------------
  // Internal: fades, errors, state, events
  // ---------------------------------------------------------------------------

  Future<void> _fade(AudioOutput out, double from, double to) async {
    if (fadeDuration <= Duration.zero || fadeSteps <= 1) {
      await out.setVolume(to);
      return;
    }
    final stepDur =
        Duration(microseconds: fadeDuration.inMicroseconds ~/ fadeSteps);
    for (var i = 1; i <= fadeSteps; i++) {
      if (_disposed) return;
      final v = from + (to - from) * (i / fadeSteps);
      await out.setVolume(v.clamp(0.0, 1.0));
      if (i < fadeSteps) await Future<void>.delayed(stepDur);
    }
  }

  /// Log the error, emit [PlaybackEventType.errorOccurred], and skip to the next
  /// item. NEVER rethrows — a bad audio file must not crash the manager.
  void _handlePlaybackError(
    PlaybackItem item,
    Object error,
    StackTrace stack, {
    required bool isMusic,
  }) {
    _logError(error, stack);
    _emit(PlaybackEventType.errorOccurred,
        item: item.copyWith(status: PlaybackItemStatus.failed),
        message: error.toString());

    if (isMusic) {
      _musicStatus = ChannelStatus.error;
      _musicLoaded = false;
      if (_index < _playlist.length - 1) {
        unawaited(next());
      } else {
        _currentMusic = null;
        if (_currentNarration == null) _setState(PlaybackState.error);
        _pushSnapshot();
      }
    } else {
      _narrationStatus = ChannelStatus.error;
      _currentNarration = null;
      if (_queue.isNotEmpty) {
        unawaited(_startNarration(_queue.removeAt(0)));
      } else {
        unawaited(_resumeOrStartMusic());
      }
    }
  }

  void _setState(PlaybackState state) {
    _state = state;
  }

  void _emit(PlaybackEventType type, {PlaybackItem? item, String? message}) {
    if (_disposed) return;
    final event = PlaybackEvent(type, item: item, message: message);
    _lastEvent = event;
    if (!_events.isClosed) _events.add(event);
    _pushSnapshot();
  }

  void _pushSnapshot() {
    if (_disposed || _snapshots.isClosed) return;
    _snapshots.add(_buildSnapshot());
  }

  PlaybackSnapshot _buildSnapshot() {
    final current = getCurrentTrack();
    return PlaybackSnapshot(
      state: _state,
      currentTrack: current,
      musicTrack: _currentMusic,
      narrationTrack: _currentNarration,
      queueLength: _queue.length,
      queue: List.unmodifiable(_queue),
      currentPriority: current?.priority,
      volume: _volume,
      muted: _muted,
      musicStatus: _musicStatus,
      narrationStatus: _narrationStatus,
      lastEvent: _lastEvent,
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _musicCompleteSub.cancel();
    await _narrationCompleteSub.cancel();
    await _music.dispose();
    await _narration.dispose();
    await _events.close();
    await _snapshots.close();
  }

  static void _defaultLog(Object error, StackTrace stack) {
    debugPrint('[PlaybackManager] audio error: $error');
  }
}
