# SCHEDULER_RECONCILIATION_PLAN

Plan only — **no production changes made**, neither scheduler deleted. Every
claim below is traced to source read for this pass.

## TL;DR

There are **two rule/announcement engines** (`RadioScheduler` and
`AutomationEngine`) that overlap, plus one true **playback brain**
(`RadioEngineService`) that both merely feed. Neither of the two controls
playback, music rotation, or the queue. Recommendation: keep
`RadioEngineService` as the single coordinator, promote **`AutomationEngine`**
to the single rule/decision layer, fold `RadioScheduler`'s DB content pools +
safety semantics + `fireNow()` into it behind a unified content provider, and
retire `RadioScheduler`'s independent timer last.

---

## The three players (only two are "schedulers")

### Coordinator (NOT one of the two) — `RadioEngineService`
`lib/features/radio/services/radio_engine_service.dart`

The actual brain and single source of playback truth:
- Owns the queue (`QueueManagerService`) and "what plays next" — `_takeNext()`
  serves the priority queue, then falls back to music (`musicScheduler.next`)
  (`radio_engine_service.dart:119`).
- Arbitrates interruptions + ducking + resume — `requestInterruption()`
  (`:171`) compares `PlaybackPriority`, pauses/resumes music.
- Runs the between‑song hook `_injectScheduledContent()` (`:329`) after each
  music track (Story → Announcement → Discovery → LocationBanter → DjBanter).
- Emits `SegmentStarted`/`SegmentCompleted`; the audio layer plays; the loop
  advances in `onSegmentCompleted()` (`:136`).

Both schedulers below only **decide + inject** into this via
`requestInterruption`.

### Scheduler A — `RadioScheduler`
`lib/features/radio/services/radio_scheduler.dart`

- **Self-contained runtime service** with its **own 30s `Timer`** (`start()`
  `:34`, `_tick()` `:81`).
- Reads **legacy tables**: `radio_schedule` (rules), `safety_messages`,
  `wildlife_alerts`, published `stories` with `audio_url` (`reload()` `:52`).
- On tick: highest‑priority due **interval** rule → rotates a
  safety/wildlife/story pool → `inject(segment)` → `requestInterruption`
  (`_segmentFor()` `:102`).
- Safety semantics: `interruptible:false`, `resumeAfter:true`,
  `PlaybackPriority.safetyWarning` (`:107`).
- Has `fireNow()` for the admin "Test announcement" button (`:73`).
- Wired per session: `_attachScheduler()` → `radioSchedulerProvider`
  (`radio_session_provider.dart:728,736`), started at `:147`/`:181`.

### Scheduler B — `AutomationEngine`
`lib/features/radio_automation/services/automation_engine.dart`

- **Pure, deterministic decision engine** — no timer, no I/O, no inject
  (returns the `RadioSegment` to play, runtime does the ducking).
- Reads **newer tables**: `radio_schedule_rules` (`RadioScheduleRule`) +
  `radio_segments` (`RadioSegment`).
- Richer rule model: station targeting, daypart (day/night/any), category,
  priority, and both **song‑boundary** triggers (`onSong()` `:99`:
  afterSong/beforeSong/everyXSongs/randomRotation) and **time** triggers
  (`onTick()` `:111`: everyXMinutes/topOfHour/halfHour/quarterHour/
  sunrise/sunset).
- Wired **through the engine**, not standalone: `DjBanterScheduler.setAutomation`
  runs `onSong` inside the between‑song hook, and a session **60s `Timer`**
  runs `onTick` → `requestInterruption`
  (`radio_session_provider.dart:109,111‑124`).

---

## Answers to the 7 questions

**1. Which should be primary.**
`RadioEngineService` is (and stays) the coordinator. Of the two rule engines,
**`AutomationEngine` (B)** should be the primary "what non‑music content plays
when" layer: pure, unit‑testable, richer trigger/daypart/station/category model,
and already integrated with the between‑song hook. `RadioScheduler` (A) folds
into it.

**2. What functionality from the other must be retained (from A).**
- Its **DB‑backed content pools** and rotation for `safety_messages`,
  `wildlife_alerts`, and published `stories` (B only knows `radio_segments`).
- **Safety semantics**: non‑interruptible, resume‑after, `safetyWarning`
  priority.
- **`fireNow()`** ("Test announcement" admin action).
- Interval cadence per rule (already expressible as B's `everyXMinutes`).

**3. Can they be merged safely?**
Yes, staged. They do **not currently conflict** (both only inject announcement
interruptions; neither owns music/queue), so `RadioEngineService`'s priority
arbitration already prevents collisions. They **do duplicate** the "schedule
rules" concept across two schemas and run on **two separate timers**. Merge =
one rule evaluator (B) + one unified content pool + one tick; safe because the
arbitration point (RadioEngineService) is untouched.

**4. Which currently controls actual playback.**
**Neither.** `RadioEngineService` controls playback (queue + `_takeNext` +
`playNext` + `requestInterruption`); `RadioAudioService`/`AudioPlayerPort`
(`radio_audio_service.dart`, JustAudio / `audio_service`) produce sound. A and B
only decide + inject.

**5. Does either duplicate music rotation / queue / content selection.**
- **Music rotation:** neither — that's `MusicScheduler` + `StationManager` /
  `SmartMusicRotationEngine`. *(Flag: those two are themselves arguably a
  second, separate dual‑path — `_takeNext` uses `MusicScheduler.next` while
  `StationManager.nextMusicSegment` uses `SmartMusicRotationEngine`. Out of
  scope here but worth a follow‑up.)*
- **Queue management:** neither — `QueueManagerService` inside
  `RadioEngineService`. Both just call `requestInterruption`.
- **Content selection / schedule rules:** **YES — duplicated.** A reads
  `radio_schedule` + domain tables on a 30s timer; B reads
  `radio_schedule_rules` + `radio_segments` on song boundaries + a 60s timer.
  Two rule schemas, two timers, overlapping "interval announcement" intent.
  **This is the core reconciliation target.**

**6. How GPS / location stories enter scheduling.**
A **separate feeder path**, not either scheduler: `radio_session_provider`
attaches `CountyWelcomeDirector`, `CommunityWelcomeDirector`, and
`LocationTriggerEngine`; `NearbyNarrationController.narrateLocation()`
(`nearby_narration_controller.dart:105`) → `resolveLocationNarration` →
`radio.requestInterruption(gpsNarration, resumeAfter:true)`. Minor overlap:
`RadioScheduler` can also inject published `stories` on its timer.
`GPSAudioScheduler` exists but is a **stub (always null)**.

**7. How DJ banter, facts, weather, local content enter scheduling.**
Mostly via the between‑song hook `_injectScheduledContent` (Story → Announcement
→ BackgroundDiscovery → **LocationBanter** → **DjBanter**). `DjBanterScheduler`
itself runs `AutomationEngine.onSong` first, then GPS banter, then **county
facts** (`CountyConfig.facts`), then voice clips / TTS templates. **Weather +
recommendations** enter separately via `CountyWelcomeDirector.scriptFor()`
(county‑welcome interruption), driven by `CountyConfig`. So "local content" is
spread across the between‑song waterfall + the county‑welcome director, all
converging on `requestInterruption` / the queue.

---

## Proposed single‑scheduler architecture

```
                 ┌─────────────────────────────────────────────┐
   MUSIC  ───────►                                              │
   (MusicScheduler / StationManager+SmartMusicRotation)         │
                 │            RadioEngineService                │
  DECISION LAYER │   (THE coordinator: queue, _takeNext,        │
  AutomationEngine ─► between-song hook + requestInterruption)  ├─► RadioAudioService
   (one rule engine over ONE unified content pool)              │      (AudioPlayerPort:
                 │                                              │       JustAudio /
  FEEDERS ───────►  county welcome (weather/recs), community,   │       audio_service)
   (directors)   │  GPS/POI stories, DJ banter, county facts,   │  → SegmentStarted/Completed
                 │  location banter                             │
                 └─────────────────────────────────────────────┘
```

- **One coordinator:** `RadioEngineService` (unchanged).
- **One rule/decision layer:** `AutomationEngine`, fed by a new
  **unified content provider** that adapts every non‑music source
  (`radio_segments` + `safety_messages` + `wildlife_alerts` + published
  `stories` + future county segments) into a common pool with categories +
  priorities. Safety keeps `interruptible:false`.
- **One clock:** a single session tick calls `AutomationEngine.onTick`; song
  boundaries call `onSong` via the existing hook. `RadioScheduler`'s standalone
  30s timer is removed.
- **Feeders stay feeders:** county welcome, community, GPS/POI stories, DJ
  banter, county facts, location banter keep flowing into
  `requestInterruption` / the between‑song hook — but documented as one
  `PlaybackPriority` ladder so there is a single arbitration point.

### What should remain
`RadioEngineService`, `AutomationEngine`, the content pools + safety semantics +
`fireNow` from `RadioScheduler`, and all feeder directors.

### What should be merged
`RadioScheduler`'s rule evaluation + timer → `AutomationEngine` + the single
session tick; its content pools → the unified content provider.

### What should eventually be removed (not yet)
`RadioScheduler` (the class + its 30s timer), and a decision on the two rule
tables — recommend standardizing on `radio_schedule_rules` and either migrating
any `radio_schedule` rows or adapting them, then dropping the `radio_schedule`
dependency. Keep `safety_messages` / `wildlife_alerts` / `stories` as content.

### How the existing audio player connects
**Unchanged.** The audio adapter (`RadioAudioService` over `AudioPlayerPort`)
subscribes to `RadioEngineService` events (`SegmentStarted` → play audio or
TTS; `SegmentCompleted` → `onSegmentCompleted` advances). This reconciliation
consolidates only the DECISION feeders, never the playback/audio path — so the
player needs no change.

---

## Suggested staged execution (after this review)

1. **Adapters, no behavior change:** add a unified announcement content provider
   (adapters over `safety_messages`/`wildlife_alerts`/`stories`) that
   `AutomationEngine` can select from; leave `RadioScheduler` running.
2. **Consolidate the clock:** route interval safety/wildlife/story rules through
   `AutomationEngine.onTick` on the single session tick; delegate
   `RadioScheduler.fireNow` to the unified path. Verify parity with tests + a
   simulated drive.
3. **Remove `RadioScheduler`** and its standalone timer once parity is proven;
   pick the canonical rule table and migrate/adapt.

Each step is independently shippable and reversible; nothing is deleted until
step 3 with verified parity.

## Explicitly out of scope for this plan
- The possible **second** dual‑path in *music selection*
  (`MusicScheduler` vs `StationManager`/`SmartMusicRotationEngine`) — flagged in
  Q5; deserves its own review.
- Local events, and populating Marion content.
