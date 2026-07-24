# ExplorerOS — Radio Engine Architecture

Explorer Radio is **not** a music player. It is an AI-controlled radio station
manager: a priority-driven decision engine that decides what plays, when
narration/alerts interrupt, and when music resumes. It manipulates a queue and
publishes playback intent + events; a future audio adapter produces the sound.

---

## 1. Folder structure

`lib/features/radio/`

| Folder | Responsibility |
| --- | --- |
| `models/` | Value types: segments, queue/state, content (song/narration/announcement/weather/safety/wildlife/commercial/station-id), profiles, rules, schedule, preferences, history. |
| `events/` | `RadioEvent` bus (segment/station/playback changes). |
| `services/` | The engine + schedulers, queue, playback controller, station manager, audio focus, offline, preferences. |
| `producer/` | The AI Producer (`ProducerEngine`) — decides; the engine executes. |
| `queue/` | Queue conventions (the queue is owned by `QueueManagerService`). |
| `stations/` | Station catalog + seed profiles. |
| `repositories/` | Content + history data access. |
| `controllers/` | `RadioEngineController` (Riverpod `Notifier`). |
| `providers/` | DI wiring. |
| `utils/` | Radio-specific helpers. |
| `documentation/` | This document. |

---

## 2. Queue architecture

`QueueManagerService` owns an ordered list of `PlaybackQueueItem`s (each wraps an
`AudioSegment`). Ordering is by `PlaybackPriority`: `insertPriority` places an
item ahead of all lower-priority ones; `enqueue` appends (music baseline);
`insertNext` forces the front. A separate "paused music" stash supports
resume-after-interruption. `getCurrentQueue()` returns an immutable
`PlaybackQueue` snapshot.

---

## 3. Priority system

Highest → lowest: **Emergency → Critical Safety → GPS Story → Scheduled
Announcement → Station Identification → Music → Ambient → Low Priority**
(`PlaybackPriority`, aliased as `AudioPriority`). Higher priorities interrupt
lower ones **only if the current item is interruptible** (emergency/safety
override regardless). Music has `resumeAfter = false`; interruptions have
`resumeAfter = true`, so music automatically resumes when they finish.

Segment types (`AudioSegmentType`): music, narration, announcement, station ID,
safety warning, emergency alert/broadcast, GPS narration, ambient, weather,
wildlife alert, commercial, special event, park announcement — grouped by
`AudioCategory` (music / spokenWord / alert / ambient / commercial) for mute
rules and analytics.

---

## 4. Playback flow

```
start()/play()
  → _takeNext(): highest-priority queued item, else MusicScheduler.next(station)
  → PlaybackController.play(item)  (+ SegmentStarted event)
audio layer finishes → onSegmentCompleted()
  → record history + SegmentCompleted
  → if the finished item was an interruption: resume stashed music (MusicResumed)
  → if it was music: schedulers may inject a story/announcement
  → playNext()
external trigger → requestInterruption(segment)
  → if current interruptible & lower priority: stash music, SegmentInterrupted, play now
  → else: insertPriority (plays when reached)
```

Public control surface: `play/pause/resume/stop/skip/previous`,
`enqueue/dequeue/insertPriority/clearQueue`, `pauseMusic/resumeMusic`,
`changeStation`, `setVolume/mute/unmute`, `getCurrentStation/getPlaybackState/getCurrentQueue`.

---

## 5. Event flow

`RadioEngineService.events` (`Stream<RadioEvent>`, sealed): `SegmentStarted`,
`SegmentCompleted`, `SegmentInterrupted`, `MusicResumed`, `StationChanged`,
`QueueCleared`, `PlaybackPaused/Resumed/Stopped`, `VolumeChanged`,
`MuteChanged`. The UI subscribes instead of polling `PlaybackState`.

---

## 6. GPS integration

The Radio Engine never polls GPS. The `TravelCompanionService`
(`features/companion/`) subscribes to the **GPS engine's** events/`TravelContext`
and forwards GPS-driven interruptions (approaching/arrived/entered-park →
location stories) into `requestInterruption`. Music resumes afterward
automatically.

---

## 7. AI Producer integration

The **AI Producer** (`ProducerEngine`) decides *what should play next / should it
interrupt* from a `ProducerContext`; the Radio Engine is responsible only for
**playback** (queueing, interrupting, resuming). The companion coordinator maps
`TravelContext` → `ProducerContext`, gets a `PlaybackDecision`, and applies it to
the engine.

---

## 8. Offline playback strategy

`OfflinePlaybackService` is the registry/seam: it answers "is this segment
downloaded, and where?" so playback can prefer a local file with no signal.
Downloaded music/narration register a local path; the future audio adapter reads
it. Content repositories already cache + serve offline via the generic base.

---

## 9. Background playback strategy

`AudioFocusManager` holds audio-focus + volume/mute intent. A real
implementation (via `audio_service`) runs playback in a background isolate/
foreground service and owns the OS audio session — enabling lock-screen
controls, Bluetooth, and continued play while backgrounded. The engine/events
are unchanged.

---

## 10. Future Android Auto & Apple CarPlay

Both attach as presentation surfaces over the same `audio_service` media session
and watch `radioEngineControllerProvider`. Browsing the station catalog maps to
the media browser tree; transport controls call `play/pause/skip/changeStation`.
No engine changes required.

---

## 11. Scalability recommendations

- Data-driven stations (`StationProfile` + `StationRule` + `StationSchedule` +
  playlists), supporting hundreds of stations and thousands of songs via paged
  repositories.
- Evolve `MusicScheduler` (shuffle, mood/daypart weighting, avoid-recent,
  local-artist bias) behind its single seam.
- Persistent history (`PlaybackRepository`) + preferences sync.
- Cache/preload upcoming segments; stream audio with a gapless player.
