import 'dart:async';

import 'package:explorer_os_mobile/features/radio/events/radio_event.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_queue.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_queue_item.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_state.dart';
import 'package:explorer_os_mobile/features/radio/banter/location_banter_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/announcement_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/audio_focus_manager.dart';
import 'package:explorer_os_mobile/features/radio/services/background_discovery_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/dj_banter_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/explore_rotation_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/gps_audio_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/history_manager.dart';
import 'package:explorer_os_mobile/features/radio/services/music_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/offline_playback_service.dart';
import 'package:explorer_os_mobile/features/radio/services/playback_controller.dart';
import 'package:explorer_os_mobile/features/radio/services/queue_manager_service.dart';
import 'package:explorer_os_mobile/features/radio/services/station_identification_service.dart';
import 'package:explorer_os_mobile/features/radio/services/station_manager.dart';
import 'package:explorer_os_mobile/features/radio/services/story_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/user_preference_manager.dart';
import 'package:explorer_os_mobile/shared/models/radio_station.dart';
import 'package:explorer_os_mobile/shared/models/song.dart';

/// The BRAIN of Explorer Radio — an intelligent decision engine, NOT an audio
/// player.
///
/// It coordinates every other service to answer four questions continuously:
///   • what should play next?      → [playNext] / [_takeNext]
///   • what should interrupt?      → [requestInterruption]
///   • when does narration begin?  → schedulers inject after music ([onSegmentCompleted])
///   • when does music resume?     → `resumeAfter` + the paused-music stash
///
/// It never produces sound. It manipulates the [QueueManagerService] and updates
/// the [PlaybackController]'s intended state; a future audio adapter observes
/// that intent and does the actual playing. Because all inputs are injected and
/// all logic is synchronous, the engine is fully unit-testable offline.
///
/// Typical lifecycle (driven by the controller, which loads content):
///   1. content is loaded and handed to [StationManager]/schedulers
///   2. [start] kicks off the first item
///   3. the audio layer reports completion → [onSegmentCompleted]
///   4. external events (alerts, future GPS) call [requestInterruption]
class RadioEngineService {
  RadioEngineService({
    required this.queue,
    required this.playback,
    required this.station,
    required this.stories,
    required this.announcements,
    required this.gps,
    required this.history,
    required this.preferences,
    this.musicScheduler = const MusicScheduler(),
    AudioFocusManager? audioFocus,
    OfflinePlaybackService? offline,
    StationIdentificationService? stationIds,
    DjBanterScheduler? djBanter,
    BackgroundDiscoveryScheduler? discovery,
    ExploreRotationScheduler? explore,
    this.locationBanter,
  })  : audioFocus = audioFocus ?? AudioFocusManager(),
        offline = offline ?? OfflinePlaybackService(),
        stationIds = stationIds ?? StationIdentificationService(),
        djBanter = djBanter ?? DjBanterScheduler(),
        discovery = discovery ?? BackgroundDiscoveryScheduler(),
        explore = explore ?? ExploreRotationScheduler();

  final QueueManagerService queue;
  final PlaybackController playback;
  final StationManager station;
  final StoryScheduler stories;
  final AnnouncementScheduler announcements;
  final GPSAudioScheduler gps;
  final HistoryManager history;
  final UserPreferenceManager preferences;
  final MusicScheduler musicScheduler;
  final AudioFocusManager audioFocus;
  final OfflinePlaybackService offline;
  final StationIdentificationService stationIds;
  final DjBanterScheduler djBanter;

  /// Fills quiet gaps between songs with nearby environmental content (wildlife,
  /// plants, birds, trees, geology, history, facts, hidden gems) so the radio
  /// keeps teaching even without a major destination.
  final BackgroundDiscoveryScheduler discovery;

  /// Weaves LOCAL banter (park/city/county narration around the user) between
  /// songs. Optional — null in tests/legacy wiring means no banter is inserted.
  final LocationBanterScheduler? locationBanter;

  /// MARION COUNTY EXPLORE's information-first rotation (WHERE YOU'RE HEADED →
  /// WHERE YOU ARE → COUNTY → WILDLIFE → NATURE → GEOLOGY → HISTORY). Only
  /// consulted when [exploreMode] is on — see [setExploreMode].
  final ExploreRotationScheduler explore;

  /// Whether the traveler has switched the player into MARION COUNTY EXPLORE.
  /// When true, [_injectScheduledContent] asks [explore] for the next segment
  /// instead of the normal Radio-mode discovery/location-banter chain; DJ
  /// banter and plain music remain the fallback either way, so the player is
  /// never silent (spec section 8).
  bool exploreMode = false;

  /// Toggles MARION COUNTY EXPLORE. Does NOT reset [explore]'s rotation
  /// position — briefly leaving and returning (e.g. the traveler drifts just
  /// outside Marion County and back) resumes where the tour left off, per
  /// spec section 7.
  void setExploreMode(bool enabled) => exploreMode = enabled;

  /// The traveler's current place name (a town, or "`<County> County`" when
  /// no town resolves) for the Explore greeting — null when not yet known.
  /// Set externally from the GPS layer, exactly like [exploreMode]/
  /// [setExploreMode]; never invented downstream. Whenever this is reliably
  /// known, a fresh Explore cold start opens with a personalized greeting
  /// (spec: "GPS LOCATION -> DETERMINE TOWN/CITY -> TIME-OF-DAY GREETING ->
  /// BEGIN LOCAL EXPLORE CONTENT") — moving or stationary, the greeting is
  /// the same either way; only whether a place name is resolvable matters.
  String? currentPlaceName;

  final StreamController<RadioEvent> _events =
      StreamController<RadioEvent>.broadcast();

  /// Events other systems subscribe to (segment/station/playback changes).
  Stream<RadioEvent> get events => _events.stream;
  void _emit(RadioEvent event) => _events.add(event);

  /// A fresh, immutable snapshot of what the engine intends right now.
  PlaybackState get state => PlaybackState(
        status: playback.status,
        current: playback.current,
        queue: queue.items,
        interruptedItem: queue.pausedMusic,
        updatedAt: DateTime.now(),
      );

  /// Starts playback by choosing and playing the first item.
  void start() => playNext();

  /// Chooses the next item and marks it as playing (or stops if nothing is
  /// available).
  void playNext() {
    final next = _takeNext();
    if (next == null) {
      playback.stop();
      return;
    }
    playback.play(next);
    _emit(SegmentStarted(DateTime.now(), next.segment));
  }

  /// The core "what plays next" decision:
  ///   1. serve the highest-priority queued item, else
  ///   2. on a genuine EXPLORE cold start, try Explore's own rotation
  ///      before ever falling to music, else
  ///   3. fall back to the station's next music track (respecting preferences).
  PlaybackQueueItem? _takeNext() {
    final queued = queue.skip();
    if (queued != null) return queued;

    // EXPLORE is discovery-first, not music-first (spec). Ordinarily
    // explore.due() is only consulted from _injectScheduledContent, which
    // itself only runs after a MUSIC segment finishes — so without this
    // check, the very FIRST thing Explore ever plays (the first Play tap, or
    // any resume after stop()/a station change) would always be a song,
    // regardless of exploreMode, simply because nothing has been queued yet.
    // Guarded by history.all.isEmpty so this only ever fires once per
    // session: the first segment played always records into history, so
    // every subsequent empty-queue moment (including the legitimate SONG GAP
    // cycle position) skips this branch and falls through exactly as before.
    if (exploreMode && history.all.isEmpty) {
      final segments = <AudioSegment>[];
      final place = currentPlaceName;
      if (place != null && place.trim().isNotEmpty) {
        segments.add(explore.greetingSegment(place));
      }
      segments.addAll(explore.due());
      for (final segment in segments) {
        if (!preferences.allowsTags(segment.tags)) continue;
        queue.insertPriority(segment, origin: QueueOrigin.scheduledStory);
      }
      final firstQueued = queue.skip();
      if (firstQueued != null) return firstQueued;
    }

    final music = musicScheduler.next(station);
    if (music == null) return null;
    if (!preferences.allowsTags(music.tags)) return _takeNext();

    // Route the fallback music through the queue so it becomes a real item.
    queue.enqueue(music, origin: QueueOrigin.enqueue);
    return queue.skip();
  }

  /// Called by the audio layer when the current segment finishes.
  ///
  /// Handles: recording history, resuming paused music after an interruption,
  /// and letting the schedulers weave in narration/announcements after music.
  void onSegmentCompleted() {
    final finished = playback.current;
    if (finished != null) {
      history.record(finished.segment);
      _emit(SegmentCompleted(DateTime.now(), finished.segment));

      // Any spoken narration (a story, a GPS story, or a discovery insert)
      // resets the discovery quiet gap — it only fills genuine silences.
      final t = finished.segment.type;
      if (t == AudioSegmentType.narration ||
          t == AudioSegmentType.gpsNarration) {
        discovery.notifyNarration();
      }

      // If an interruption just ended, restore the music it displaced.
      if (finished.segment.resumeAfter && queue.pausedMusic != null) {
        queue.resumeMusic();
        _emit(MusicResumed(DateTime.now()));
      }

      // After a music track, schedulers may inject scheduled content.
      if (finished.segment.type == AudioSegmentType.music) {
        _injectScheduledContent(finished.segment);
      }
    }

    playback.complete();
    playNext();
  }

  /// Requests that [segment] interrupt playback (safety/emergency alerts,
  /// scheduled announcements, and — later — GPS narration).
  ///
  /// Interrupts immediately only if something interruptible of lower priority is
  /// playing; otherwise the item is queued by priority and plays when reached.
  void requestInterruption(AudioSegment segment) {
    final current = playback.current;
    // Interrupt immediately when the new item outranks the current interruptible
    // one, OR when a newer temporary report replaces the current temporary
    // report. The latter is critical: tapping a second destination must switch
    // to it right away — same-priority reports would otherwise queue behind the
    // first, so you'd keep hearing the previous (wrong) narration.
    final supersedesReport =
        current != null && current.segment.resumeAfter && segment.resumeAfter;
    if (current != null &&
        current.segment.interruptible &&
        (segment.priority.isHigherThan(current.segment.priority) ||
            supersedesReport)) {
      // Stash displaced MUSIC so it resumes after the report ends. When we're
      // replacing one report with another, the music displaced by the FIRST
      // report is already stashed — don't overwrite it with the outgoing report.
      if (current.segment.type == AudioSegmentType.music) {
        queue.pauseMusic(current);
      }
      _emit(SegmentInterrupted(DateTime.now(), current.segment));
      playback.complete();
      queue.insertPriority(segment, origin: QueueOrigin.insertPriority);
      playNext();
    } else {
      queue.insertPriority(segment, origin: QueueOrigin.insertPriority);
    }
  }

  // --- Public control surface (all intent-level; no audio I/O) -------------

  /// Starts or resumes playback.
  void play() {
    if (playback.status == PlaybackStatus.paused) {
      resume();
    } else if (playback.current == null) {
      playNext();
    }
  }

  /// Skips the current item and advances to the next decision.
  ///
  /// While a temporary interruption (a segment with [resumeAfter]) is playing,
  /// Skip cancels it and resumes the displaced music at the exact spot it
  /// paused — no restart, no waiting.
  void skip() {
    final current = playback.current;
    if (current != null &&
        current.segment.resumeAfter &&
        queue.pausedMusic != null) {
      _emit(SegmentCompleted(DateTime.now(), current.segment));
      queue.resumeMusic();
      _emit(MusicResumed(DateTime.now()));
      playback.complete();
      playNext();
      return;
    }
    playback.complete();
    playNext();
  }

  /// Replays the most recently played segment (from history).
  void previous() {
    final last = history.snapshot.last;
    if (last == null) return;
    queue.insertNext(last, origin: QueueOrigin.insertNext);
    playback.complete();
    playNext();
  }

  void pause() {
    playback.pause();
    _emit(PlaybackPaused(DateTime.now()));
  }

  void resume() {
    playback.resume();
    _emit(PlaybackResumed(DateTime.now()));
  }

  /// Stops the engine entirely and clears the queue.
  void stop() {
    playback.stop();
    queue.clear();
    _emit(PlaybackStopped(DateTime.now()));
  }

  // Queue operations (delegate to the queue manager).
  void enqueue(AudioSegment segment) => queue.enqueue(segment);
  PlaybackQueueItem? dequeue() => queue.skip();
  void insertPriority(AudioSegment segment) => queue.insertPriority(segment);
  void clearQueue() {
    queue.clear();
    _emit(QueueCleared(DateTime.now()));
  }

  /// Re-inserts the stashed music at the front and plays it.
  void resumeMusic() {
    if (queue.resumeMusic() != null) {
      _emit(MusicResumed(DateTime.now()));
      if (playback.current == null) playNext();
    }
  }

  /// Stashes the current music (if any) and pauses.
  void pauseMusic() {
    final current = playback.current;
    if (current != null && current.segment.type == AudioSegmentType.music) {
      queue.pauseMusic(current);
    }
    pause();
  }

  /// Switches to a different station, reloading its playlist/rules/IDs.
  ///
  /// Pass [autoPlay] = false to load without starting (e.g. so a UI Play button
  /// initiates playback — required by web autoplay policies).
  void changeStation(
    RadioStation newStation, {
    List<Song> songs = const [],
    List<AudioSegment> stationIdSegments = const [],
    bool autoPlay = true,
  }) {
    playback.stop();
    queue.clear();
    station.load(station: newStation, playlist: songs);
    _emit(StationChanged(DateTime.now(), newStation.id));
    if (autoPlay) playNext();
  }

  // Volume / mute (via the audio-focus manager).
  void setVolume(double volume) {
    audioFocus.setVolume(volume);
    _emit(VolumeChanged(DateTime.now(), audioFocus.volume));
  }

  void mute() {
    audioFocus.mute();
    _emit(MuteChanged(DateTime.now(), true));
  }

  void unmute() {
    audioFocus.unmute();
    _emit(MuteChanged(DateTime.now(), false));
  }

  // Getters.
  RadioStation? getCurrentStation() => station.station;
  PlaybackState getPlaybackState() => state;
  PlaybackQueue getCurrentQueue() => queue.snapshot;

  void dispose() => _events.close();

  void _injectScheduledContent(AudioSegment finishedMusic) {
    // A song just aired — advance the discovery quiet-gap counter.
    discovery.tick();

    final due = <AudioSegment>[];
    if (exploreMode) {
      // MARION COUNTY EXPLORE gets EXCLUSIVE control of the narration slot —
      // checked on every song boundary (no quiet-gap wait). Previously
      // stories/announcements ran unconditionally BEFORE this check, so
      // whenever either fired (their own cadence, unrelated to Explore's
      // programmed format), explore.due() was skipped entirely and its
      // cycle position never advanced — starving WILDLIFE of its guaranteed
      // turn and letting extra songs play with nothing scheduled at all.
      // Explore now always gets to run its own INFORMATION -> WILDLIFE ->
      // SONG cycle without competing with Radio-mode's schedulers. DJ
      // banter + plain music remain the final fallback (never silent).
      due.addAll(explore.due());
    } else {
      if (preferences.narrationsEnabled) {
        final narration = stories.onMusicPlayed();
        if (narration != null) due.add(narration);
      }
      if (preferences.announcementsEnabled) {
        final announcement = announcements.onMusicPlayed();
        if (announcement != null) due.add(announcement);
      }
      if (due.isEmpty) {
        // Background discovery: when it's been quiet for a while, teach
        // something about the nearby environment (before falling back to
        // generic DJ banter).
        if (preferences.narrationsEnabled) {
          final discovered = discovery.due();
          if (discovered != null) due.add(discovered);
        }
        // Local banter: a short narration about the park/city/county the user
        // is in (park > city > county), reusing the location's own AI
        // content. Sits above generic DJ banter so the station feels
        // genuinely local.
        if (due.isEmpty && preferences.narrationsEnabled && locationBanter != null) {
          final local = locationBanter!.onMusicPlayed();
          if (local != null) due.add(local);
        }
      }
    }
    // DJ banter fills the space between songs when nothing else is scheduled,
    // so the station sounds hosted rather than a bare playlist.
    if (due.isEmpty) {
      final banter = djBanter.onMusicPlayed(finishedMusic,
          radioStationName: station.station?.name);
      if (banter != null) due.add(banter);
    }

    for (final segment in due) {
      if (!preferences.allowsTags(segment.tags)) continue;
      final origin = segment.type == AudioSegmentType.narration
          ? QueueOrigin.scheduledStory
          : QueueOrigin.scheduledAnnouncement;
      queue.insertPriority(segment, origin: origin);
    }
  }
}
