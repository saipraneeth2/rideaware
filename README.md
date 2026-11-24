# RideAware (research prototype)

> [!WARNING]
> **No testing done.** This prototype has not been tested on a real iPhone, with AirPods or any
> Bluetooth headset, or on a bike. It has only been compiled and launched in the iOS Simulator,
> and the automated unit tests in `RideAwareTests` were run there. Everything in
> [docs/DEVICE_TEST_MATRIX.md](docs/DEVICE_TEST_MATRIX.md) is still unrun. Do not rely on it while riding.

A native iPhone prototype that gives cyclists short spoken awareness alerts through AirPods
and private group-ride messages. Its research question is whether useful **acoustic** awareness
of approaching vehicles can work **without** extra radar hardware.

Radar headphone warnings and group intercoms already exist as products. RideAware is an
**awareness aid**: it does not prevent collisions, does not guarantee detection, and treats
silence as "nothing reported", never as "safe".

> **Milestone 1 is implemented.** Acoustic vehicle detection is **not available** in this
> build: no validated model exists yet. The microphone pipeline is real and is used for
> audio-feasibility measurements. Detection events come only from clearly labelled simulators.

## Contents

| Document | Purpose |
|---|---|
| [docs/FEASIBILITY.md](docs/FEASIBILITY.md) | Toolchain, verified APIs, AirPods HQ recording constraints, risks |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Component diagram, audio session ownership, extension points |
| [docs/TEST_RESULTS.md](docs/TEST_RESULTS.md) | Automated test results and coverage gaps |
| [docs/DEVICE_TEST_MATRIX.md](docs/DEVICE_TEST_MATRIX.md) | Physical-device test plan (not yet run) |
| [docs/DATASET_AND_MODEL_PLAN.md](docs/DATASET_AND_MODEL_PLAN.md) | How to get to real inference, metrics, splits |
| [docs/RADAR_INTEGRATION_CHECKLIST.md](docs/RADAR_INTEGRATION_CHECKLIST.md) | Steps before supporting any radar |

## Requirements

- Xcode 27.2 or later (built and tested with 27.2 / Swift 6.4.2)
- iOS 26.0 or later. iOS 26 is needed for `AVInputPickerInteraction` and
  `.bluetoothHighQualityRecording`.
- No third-party packages, accounts or API keys for Milestone 1.

## Run in the simulator

```bash
open RideAware.xcodeproj
```

Choose the **RideAware** scheme and an iPhone simulator, then Run. Or from the terminal:

```bash
xcodebuild -project RideAware.xcodeproj -scheme RideAware -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.2' test
```

In the simulator the microphone uses the Mac's input, there is no Bluetooth, and speech plays
through the Mac. That is enough for the UI, simulation and logic, but not for any audio-route
conclusion.

### Try it

1. Read the onboarding screen and tap **I understand these limitations**.
2. **Diagnostics → Simulation mode** on, then pick a scenario (Approaching traffic, Repeated
   detections, Silence, Sensor failure, Stale input) or the radar simulator.
3. **Ride → Start ride.** Watch *Monitoring health* and *Traffic events*, and listen for
   "Simulation. Possible vehicle sound."
4. **Diagnostics → Alert decisions** shows each event as Announced, Suppressed (duplicate or
   cooldown) or Rejected (stale).
5. **Group:** create a group, note the code, add a simulated rider and send a simulated report.
   It is attributed to "Sim Rider 1 (simulated rider)" and spoken with that name.

## Run on an iPhone (physical device)

1. Copy `Config/Local.example.xcconfig` to `Config/Local.xcconfig` (git-ignored). Set
   `DEVELOPMENT_TEAM` to your Team ID and `RIDEAWARE_BUNDLE_ID_PREFIX` to a reverse-DNS prefix
   you own. Alternatively, choose your team in Xcode under Signing & Capabilities.
2. Connect the iPhone, enable Developer Mode on it (Settings › Privacy & Security), select it as
   the run destination, and Run.
3. On first ride start, iOS asks for microphone permission.
4. To test AirPods: pair them, then in **Settings › Microphone** choose *Automatic* (AirPods as
   output only), *Bluetooth headset* (HFP mic) or *AirPods high-quality recording*. Check
   **Diagnostics › Audio session** for the actual input, output, sample rate and the
   high-quality-recording status.
5. Work through [docs/DEVICE_TEST_MATRIX.md](docs/DEVICE_TEST_MATRIX.md).

## Working vs simulated vs unavailable

| Feature | Status |
|---|---|
| Onboarding with limitations | ✅ Working |
| Ride start/stop, timer, local ride storage (JSON, no audio or location) | ✅ Working, unit-tested |
| Microphone permission request and denied state | ✅ Working, unit-tested with fakes |
| Microphone capture (`AVAudioEngine`), level meter, buffer cadence, format | ✅ Working in simulator; **device untested** |
| Display of actual input/output routes and available inputs | ✅ Working; Bluetooth **device untested** |
| Mic selection: preference picker plus system `AVInputPickerInteraction` | ✅ Implemented; **device untested** |
| AirPods high-quality recording option with runtime support check | ✅ Implemented; **hardware untested**; regional availability unknown |
| Spoken alerts via `AVSpeechSynthesizer` through current output | ✅ Working in simulator; AirPods **untested** |
| Route change, headphone disconnect, interruption, media reset handling | ✅ Implemented; logic tested; **device behaviour untested** |
| Single audio session coordinator (no feature overwrites settings) | ✅ Implemented, planner unit-tested |
| Alert de-duplication, cooldown, stale and future rejection, source timestamps | ✅ Working, unit-tested |
| Monitoring health shown separately from events, spoken health changes | ✅ Working, unit-tested |
| Simulation: approaching traffic, repeated, silence, sensor failure, stale | 🟧 **Simulated** (labelled) |
| Radar adapter | 🟧 **Simulator only**; no device supported |
| Acoustic vehicle detection | ⛔ **Unavailable**: no validated model |
| Consent-gated sample recording, playback, delete | ✅ Working; labelling is Milestone 2 |
| Group create/join with expiring codes, presence, reports, attribution | 🟧 **Local only**: no network transport; codes only resolve on the same iPhone |
| Simulated riders | 🟧 **Simulated** (labelled) |
| Location sharing | ⛔ Policy implemented and tested; **disabled** until a network transport exists |
| Group voice (WebRTC or managed service) | ⛔ Not implemented (Milestone 3) |
| Background operation | ⚠️ `audio` background mode declared; **must be verified on device** |

## What requires physical hardware or external credentials

- **Physical iPhone**: all audio routing, Bluetooth, interruption (calls), lock-screen and
  background behaviour, battery and latency measurements, and wind and acoustic data.
- **AirPods (or another Bluetooth headset)**: HFP input, A2DP output and headphone-disconnect
  handling. High-quality recording additionally needs a supported AirPods model on current
  firmware; Apple names AirPods 4, AirPods 4 with ANC and AirPods Pro 2.
- **Apple Developer account / Team ID**: needed to install on a device (free accounts work for
  personal devices with limits).
- **Network backend and voice provider credentials** (Milestone 3): not chosen yet. A
  template for these is in `Config/secrets.example.env`. Never commit real values.
- **Radar hardware plus published protocol documentation**: for any radar support.

## Known limitations

- No real vehicle detection. Microphone loudness is never used as detection.
- While sensing, alerts mix over music without ducking, because ducking would last the whole ride.
  Ducking is used only for prompts when the microphone is off.
- With *Bluetooth headset (HFP)*, playback quality drops to call quality for all audio.
- In simulation with the microphone off, the app probably suspends when locked (no active audio
  between prompts). Unverified.
- With "Use iPhone speaker if headphones disconnect" turned off, there is no audible way to tell
  the rider that the headphones were lost. The incident is shown on screen and recorded.
- iOS 27 interruption notifications are handled alongside the deprecated legacy notification.
  The behaviour has not been verified on a device.
- Group codes and reports never leave the device. Presence states other than "connected" are
  modelled but not yet produced.
- Invite codes are 6 characters. A real backend must rate-limit joins and bind codes server-side.
- No UI test target yet, and no app icon.

## Prioritised next steps

1. **Run device matrix sections A–C** on at least one iPhone with AirPods Pro 2 or AirPods 4, on
   both iOS 26.x and 27.x. Fix any route, interruption or background issues found.
2. **Collect consented audio (matrix D)** with the existing sample recorder. Add labelling UI and
   export (Milestone 2).
3. **Run Apple's built-in classifier offline** on labelled clips, using session- and
   location-separated splits. Report missed events, false alerts per hour and lead time against
   thresholds agreed in advance.
4. Only if it passes: implement the `SNAudioStreamAnalyzer`-based `DetectionProvider`, labelled
   experimental.
5. **Choose the group transport** (managed realtime service versus own backend). Document setup and
   cost, then implement presence, reports, disconnect/reconnect, and CoreLocation sharing behind the
   existing policy.
6. **Group voice** as a separate mode via a maintained WebRTC stack or managed service. Measure
   range and network behaviour before making any claims.
7. Add a UI test target for the ride, simulation and group flows, an app icon, and localisation of
   spoken phrases.
