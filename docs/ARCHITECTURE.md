# Architecture

SwiftUI app, Swift 6 language mode with complete strict concurrency, deployment target iOS 26.0.
No third-party dependencies.

```
                      ┌────────────────────── AppEnvironment (composition root) ──────────────────────┐
                      │                                                                                │
 UI (SwiftUI) ───────▶│  RideController ──▶ DetectionProvider ◀── Simulated / ExperimentalAcoustic /    │
  Ride, Group,        │       │   │                                 SimulatedRadarAdapter               │
  Settings,           │       │   └──▶ AlertCoordinator ──▶ AlertGate (dedup, cooldown, stale)          │
  Diagnostics,        │       │              │                                                          │
  Onboarding          │       │              └──▶ SpeechAlertSpeaker ─┐                                  │
                      │       ├──▶ MicrophoneMonitor ──▶ MicrophoneCapture (AVAudioEngine tap)          │
                      │       │          │                            │                                  │
                      │       │          └──── acquire/release ──▶ AudioSessionCoordinator ──▶ AVAudioSession
                      │       │                                       ▲  (only writer)                  │
                      │       ├──▶ LocationSharingController           │                                 │
                      │       └──▶ RideHistory ──▶ JSONFileRideStore   SamplePlayer, SampleLibrary       │
                      │                                                                                │
                      │  GroupSession ──▶ LocalGroupRegistry (no network)   AppSettings (UserDefaults)  │
                      └────────────────────────────────────────────────────────────────────────────────┘
```

## Principles

| Principle | Where it is enforced |
|---|---|
| One owner of audio-session settings | `AudioSessionCoordinator` is the only type that calls `setCategory`, `setActive` or `setPreferredInput`. Features hold *demands* (`microphoneSensing`, `spokenPrompt`, `samplePlayback`, `voiceChat`). `SessionPlanner` turns the union into one plan; the coordinator applies it only when it changes. |
| Voice and sensing are separate modes | `SessionPlanner` throws `conflictingDemands` for `voiceChat` + `microphoneSensing` (tested). |
| Monitoring health is separate from traffic events | `StreamHealth` and `MonitoringSnapshot` versus `DetectionEvent` and `AlertLogEntry`; separate dashboard cards. |
| No detection is never "clear" | `MonitoringSnapshot` headlines and `AlertPhrase` texts are tested against a prohibited-fragment list ("clear", "safe", "behind you", "metres"…). |
| Conservative labels | `DetectionKind.possibleVehicleSound`; no direction, distance or speed fields exist on `DetectionEvent`. |
| Source attribution | `DetectionSource` for sensors; `GroupReport.sender` for riders. Group reports never enter `AlertCoordinator.handle`. |
| Simulation always labelled | `DetectionSource.isSimulated` drives the "Simulation." speech prefix, the orange banner, and `RideSession.detectorIsSimulated`. |

## Key types

### Audio (`RideAware/Core/Audio`)
- **`SessionPlanner`**: pure function from demands and preferences to `SessionPlan`. Sensing
  uses `.playAndRecord` / `.default` / `.mixWithOthers` + `.defaultToSpeaker`, plus:
  - Automatic or iPhone mic: `.allowBluetoothA2DP`. AirPods stay output-only and music quality is preserved.
  - Bluetooth headset: `.allowBluetoothHFP`. Narrow-band input and output.
  - AirPods high quality: `.bluetoothHighQualityRecording` + `.allowBluetoothHFP` fallback, `.default` mode (Apple requirement).
  - Prompts only: `.playback` / `.voicePrompt`, with `.duckOthers` if enabled. No ducking while
    sensing, because ducking lasts as long as the session is active.
- **`AudioSessionCoordinator`**: applies plans, publishes `AudioRouteSnapshot`, session details,
  high-quality-recording status and input mismatch, and normalises notifications into
  `AudioSessionEvent`. It handles the route change, legacy interruption, iOS 27
  inactive/resumption, media-services reset and available-inputs notifications.
- **`MicrophoneCapture`**: `AVAudioEngine` tap, not actor-isolated (audio thread), with lock-protected
  state. It computes the RMS/peak level (diagnostics only), writes consented samples, and reports
  engine configuration changes.
- **`MicrophoneMonitor`**: permission, start/stop, and auto-restart after interruption,
  configuration change or media reset, with a 5 s retry on failure. Health comes from
  `StreamHealthEvaluator` (stale after 2 s with no buffers).
- **`SpeechAlertSpeaker`**: `AVSpeechSynthesizer` with the app session. It acquires
  `spokenPrompt`, and detection alerts can interrupt lower-priority speech.

### Detection (`RideAware/Core/Detection`)
- **`DetectionProvider`** protocol: `descriptor`, `availability`, `isRunning`, `lastInputAt`,
  `failureReason`, `onEvent`, `start/stop`.
- **`SimulatedDetectionProvider`** plays a `SimulationScript` (approaching traffic, repeated
  detections, silence, sensor failure, stale input). Its `advance(to:)` is deterministic so tests
  can drive it.
- **`ExperimentalAcousticProvider`** is always `.unavailable` in this build.
- **`RadarAdapter`** protocol plus **`SimulatedRadarAdapter`**. No real device is supported.

### Alerts (`RideAware/Core/Alerts`)
- **`AlertGate`**: rejects stale (> 2 s) and future (> 0.5 s) events, then applies a sliding
  de-duplication window (4 s per `dedupKey`) and a per-kind cooldown (10 s). Stale events do not
  consume cooldown.
- **`AlertCoordinator`**: logs every decision, counts announced/suppressed/rejected events, and speaks
  if settings and the output route allow it.
- **`AlertPhrase`**: every spoken sentence in one place.

### Ride, group, location, storage
- **`RideController`** starts the microphone, detector and location policy together. It ticks
  every 0.5 s, builds the `MonitoringSnapshot`, records health incidents, and speaks health
  changes through `HealthAnnouncer` (rate-limited, never repeats a brief flap). On stop it
  persists a `RideSession`.
- **`GroupSession`**: create/join/leave with `InviteCode` (6 characters, unambiguous alphabet,
  30-minute expiry), presence, explicit reports, echo and duplicate suppression, and simulated
  riders. The transport is `.localOnly`.
- **`LocationSharingController`**: shares only if opted in, a ride is active, the rider is in a
  group and a transport exists. The opt-in is cleared on ride end or leaving the group. No
  CoreLocation provider ships yet.
- **`JSONFileRideStore`**: `Application Support/RideAware/rides.json`, excluded from backup, with
  `completeUnlessOpen` file protection. It holds no audio and no location.
- **`SampleLibrary`**: consent-gated `.caf` clips, at most 15 s each, in `Application Support/RideAware/Samples`,
  excluded from backup. A visible red banner shows while recording, and samples can be deleted one
  at a time or all at once.

## Concurrency model
- UI-facing services are `@MainActor @Observable`.
- The audio tap runs on an audio thread inside `MicrophoneCapture` (`@unchecked Sendable` + `NSLock`)
  and hops to the main actor with `Task { @MainActor in … }`.
- `AVAudioSession` notifications are observed on `.main` and handled through `MainActor.assumeIsolated`.
- ObjC delegate callbacks (`AVSpeechSynthesizerDelegate`, `AVAudioPlayerDelegate`) are `nonisolated` and
  hop to the main actor. The project does not enable inferred isolated conformances, to avoid runtime
  isolation traps on audio threads.

## Extension points for later milestones
- **M2 acoustic inference**: implement `DetectionProvider` by feeding `MicrophoneCapture` buffers to
  `SNAudioStreamAnalyzer`. Set `lastInputAt` per analysed frame so stale input is detected, and keep
  `rawScore` for diagnostics only.
- **M3 group transport**: replace `LocalGroupRegistry` and call `GroupSession.receive(...)` from the
  network layer. Provide a CoreLocation `LocationProviding` and set `transportAvailable: true`.
- **Group voice**: acquire `voiceChat` from the coordinator. The planner already refuses to combine it
  with sensing.
- **Radar**: implement `RadarAdapter` for one verified device (RADAR_INTEGRATION_CHECKLIST.md).
