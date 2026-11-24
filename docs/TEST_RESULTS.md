# Test results

Run 2026-11-24 with Xcode 27.2 and Swift Testing. Hosted unit tests (`RideAwareTests`).

| Destination | Result |
|---|---|
| iPhone 17 simulator, iOS 27.2 | **88 tests in 17 suites passed** |
| iPhone 17 simulator, iOS 26.4 (deployment minimum) | **88 tests in 17 suites passed** |
| App build, Debug, iOS 27.2 simulator | Succeeded, 0 warnings, Swift 6 strict concurrency |
| Launch on the iPhone 18 Pro simulator (iOS 27.2) | Onboarding and Ride screens render (see `screenshots/`) |
| Physical device | **Not run.** No iPhone or AirPods were attached. |

## Suites

| Suite | What it covers |
|---|---|
| Alert de-duplication, cooldown and stale rejection | Sliding de-duplication, a continuous sound giving exactly one alert, per-kind cooldown, max-age boundary, stale events not consuming state, future timestamps, out-of-order duplicates |
| Alert coordinator | Conservative wording, "Simulation." prefix, logging of suppressed and rejected events, speech disabled, reset per ride |
| Stream health | Off, starting, live and stale transitions; input before a restart ignored; precedence of permission denied over failure over interruption |
| Monitoring snapshot never claims safety | A live microphone alone is not monitoring; headlines contain no "safe" or "clear" |
| Spoken health announcements | Baseline silence, loss announced with reason, flap suppression, delayed recovery announcement |
| Microphone permission (real `MicrophoneMonitor`) | Denied makes the mic unavailable without touching the session; undetermined is requested once; stop clears state |
| Simulation scenarios | Each scenario run through the real gate and evaluator: approaching traffic (2 alerts per cycle, loops), repeated detections (2 announced, 7 duplicates, 1 cooldown), silence (no events, stays live), sensor failure (live, then stale, then failed), stale input (2 rejected, 1 accepted), radar simulator labelled, acoustic provider unavailable |
| Invitation codes | Alphabet, normalisation, expiry boundary |
| Group create, join and leave | Joining via registry, expired, malformed and unknown codes, double join |
| Group report attribution | Sender kept, never a local detection, age from local receive time, local reports labelled "You" and not spoken, echo and duplicate suppression, simulated riders labelled |
| Ride lifecycle | Start/stop shuts down mic and detector and persists the session; events after stop are ignored; double start is a no-op; unavailable detector; denied mic; sensor failure surfaced, spoken and recorded; stale detector |
| Location sharing | Off by default, shares only during an active group ride, ride end stops it and clears the opt-in, leaving the group stops it mid-ride, opting out stops it, never shares without a transport |
| Audio session planning | No demands means inactive; voice + sensing conflict; prompts don't reconfigure sensing; mixable, non-ducking sensing; prompt ducking; HQ Bluetooth options and mode |
| Route changes | Headphone loss to speaker detected; headphone-to-headphone switch is not a loss; port classification |
| Level meter | Silence floor, full-scale sine ≈ −3 dBFS, half amplitude ≈ −6 dBFS |
| Spoken wording | Every phrase checked against the prohibited list (parameterised) |
| Local ride storage | JSON round trip, delete all, missing file |

## How to rerun

```bash
xcodebuild -project RideAware.xcodeproj -scheme RideAware -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.2' test
```

## Not covered by automated tests

- Real `AVAudioSession` behaviour under route changes, calls, Bluetooth and the background
  (device-only; see DEVICE_TEST_MATRIX.md).
- `AVSpeechSynthesizer` output, ducking and audibility.
- SwiftUI interaction flows (no UI test target yet).
- Sample recording and playback on real audio hardware.
