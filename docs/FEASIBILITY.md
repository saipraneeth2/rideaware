# Feasibility assessment

Assessed 2026-11-24 against the installed toolchain: **Xcode 27.2 (27B52), iOS 27.2 SDK,
Swift 6.4.2**. Simulators available: iOS 26.4, 26.5, 27.2. No physical iPhone or AirPods were
connected during this assessment, so every hardware claim below is *documented* or *untested*,
never *measured*.

## Question

Can an iPhone, optionally with AirPods microphones, give a cyclist useful acoustic awareness of
approaching vehicles without a dedicated radar? Radar headphone warnings and group intercoms
already exist as products; this project does not claim novelty, only investigates the
radar-free acoustic path.

## What the public platform provides (verified)

| Capability | Source | Status |
|---|---|---|
| Microphone capture with `AVAudioEngine` input tap | AVFAudio | Implemented. Runs on simulator (Mac mic). |
| Record permission via `AVAudioApplication` (iOS 17+) | SDK header `AVAudioApplication.h` | Implemented. |
| Current route, available inputs, preferred input | `AVAudioSession` | Implemented. |
| System microphone picker `AVInputPickerInteraction` | SDK header `AVKit/AVInputPickerInteraction.h`, iOS 26.0 | Implemented (Diagnostics). |
| Output picker `AVRoutePickerView` | AVKit | Implemented (Diagnostics). |
| Full-bandwidth Bluetooth recording `.bluetoothHighQualityRecording` | SDK header + Apple docs, iOS 26.0 | Implemented as an option; **untested on hardware**. |
| Per-port capability query `bluetoothMicrophoneExtension.highQualityRecording.isSupported/isEnabled` | SDK header `AVAudioSessionRoute.h`, iOS 26.0 | Read and displayed. |
| Far-field Bluetooth input `.farFieldInput` | SDK header, iOS **26.2** | Reported in route snapshot only; not requested. |
| Spoken prompts `AVSpeechSynthesizer` through the app session | AVFAudio | Implemented. |
| iOS 27 `didBecomeInactive` / `resumptionRecommendation` notifications (legacy interruption notification deprecated in 27.0) | SDK header `AVAudioSessionTypes.h` | Both paths observed, handled idempotently. |
| Built-in sound classifier `SNClassifySoundRequest(.version1)` | SoundAnalysis, enumerated on this Mac | 303 labels; see below. **Not used yet.** |

### High-quality Bluetooth recording: constraints from Apple's documentation

- Works "when the Bluetooth route supports it, such as on certain AirPods models". Apple's June
  2025 newsroom post names AirPods 4, AirPods 4 with ANC and AirPods Pro 2 (firmware update with
  iOS 26). Later models are not listed there; the app queries the port at runtime and never
  assumes support from a model name.
- Only compatible with `AVAudioSession.Mode.default`. `allowBluetoothHFP` can be combined as a
  fallback.
- "May increase input latency … not recommended for real-time communication usage." It is
  therefore never combined with group voice.
- Apple suggests `setPrefersNoInterruptionsFromSystemAlerts(_:)` during such recording. Not
  enabled: a cyclist probably wants calls to interrupt. Needs a product decision.
- Apple's footnote: "Some features may not be available in all languages or regions." Regional
  availability is therefore unknown per market and must be checked on-device in each test region.

### Things the platform does **not** provide (assumed unavailable)

- Separate raw streams from the left and right AirPods microphones. Not exposed; no direction
  of arrival from AirPods.
- Access to Transparency mode or Active Noise Cancellation processing, or their microphone feeds.
- Any guarantee that iPhone-mic capture + Bluetooth output + background execution all work
  together on every device. Must be measured (see DEVICE_TEST_MATRIX.md).

## Models

Apple's built-in SoundAnalysis classifier (enumerated on the host Mac with macOS 27; the iOS
label set should be confirmed on device) includes these vehicle-related labels:
`car_passing_by`, `engine`, `engine_accelerating_revving`, `engine_idling`, `engine_starting`,
`truck`, `bus`, `motorcycle`, `traffic_noise`, `vehicle_skidding`, `car_horn`, plus
`wind_noise_microphone` and `bicycle`.

It is a real model shipped with the OS and usable by apps. It has **not** been shown to be
appropriate here: it was not built for rear-approach warning, for wind-loaded microphones on a
moving bike, or for electric vehicles, and its confidence scores are uncalibrated for this task.
Milestone 1 therefore keeps acoustic vehicle detection **visibly unavailable**. The classifier
is the first candidate to evaluate offline in Milestone 2 (DATASET_AND_MODEL_PLAN.md).

No third-party model or dataset was added. No volume threshold or random value is used as
"detection" anywhere in the app.

## Main technical risks

1. **Wind noise.** At cycling speeds, wind on the microphone is likely to mask tyre and engine
   noise. This is the single largest risk and is untested.
2. **Quiet vehicles.** Electric and hybrid vehicles at low speed may produce little sound before
   they are close.
3. **Lead time.** Even a correct detection is only useful if it arrives several seconds before the
   vehicle passes. Unmeasured.
4. **Route trade-offs.** Using AirPods mics via HFP degrades both input and music output to call
   quality. The iOS 26 high-quality option avoids that only on supported models and adds latency.
5. **Background execution.** The `audio` background mode is declared; whether capture and speech
   continue with the screen locked, during calls, and after route changes must be verified.
6. **Battery.** Continuous capture plus inference for multi-hour rides is unmeasured.

## Decision

Build Milestone 1 now: a real audio pipeline, honest status reporting, simulation, and the
measurement tooling needed to answer the question with data. Do not ship or describe any
vehicle detection until an evaluated model meets thresholds agreed in advance.
