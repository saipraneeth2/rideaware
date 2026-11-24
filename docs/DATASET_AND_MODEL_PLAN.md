# Dataset and model plan (real inference is unavailable)

## Status

No validated vehicle-sound model ships with RideAware. `ExperimentalAcousticProvider` reports
itself unavailable and emits nothing. This document describes the work needed before that
can change.

## Step 1: Evaluate the built-in classifier offline first

Apple's `SNClassifySoundRequest(classifierIdentifier: .version1)` is available to apps and includes
`car_passing_by`, `engine`, `engine_accelerating_revving`, `truck`, `bus`, `motorcycle`,
`traffic_noise` and `wind_noise_microphone`. Before any on-bike use:

1. Run it **offline** over a labelled evaluation set (below) using `SNAudioFileAnalyzer`.
2. Sweep window duration and overlap (the request exposes `windowDuration` and `overlapFactor`).
3. Build candidate decision rules from label scores, for example "max(vehicle labels) over N
   consecutive windows". Fix the rule **before** looking at the held-out test split.
4. Report the metrics below. If the targets are not met, the classifier is rejected for this use.

Use only the labels, never `rawScore`, as rider-facing output. Uncalibrated scores are never
shown as probabilities.

## Step 2: Data collection (consent-based, already supported)

The app records consented 15 s `.caf` clips (Diagnostics › Audio samples). Milestone 2 adds:

- **Labelling UI**: per clip, mark vehicle onset, closest pass time, vehicle type (car, truck/bus,
  motorcycle, EV/hybrid if known, none) and approach direction from ground truth (not inferred).
- **Context metadata**: input route, mount (pocket, bar, AirPods), speed (from GPS if the rider
  opts in), wind estimate, road type, weather, and recording session ID.
- **Ground truth**: a synchronised rear camera or a validated radar unit logging target times.
  Annotations come from ground truth, never from the model under test.
- **Export**: local share-sheet export of the clip plus a JSON label, with the rider's
  explicit action. No automatic upload.

Participants must give informed consent to recording. Clips may capture other people's speech:
record in controlled settings, and strip or reject clips containing identifiable speech.

## Step 3: Splits

- Split by **recording session and location**, never by clip. No session or location appears in
  more than one of train, validation and test.
- Keep a fully held-out test set collected on different days and routes.
- Stratify reporting by input route, mount, speed band, vehicle type and wind band.

## Step 4: Metrics to report (for any model)

| Metric | Definition |
|-|-|
| Missed events | Fraction of ground-truth approaching vehicles with no alert before closest pass |
| False alerts per hour | Alerts with no ground-truth vehicle within the matching window, per hour of riding audio |
| Warning lead time | Closest-pass time minus first-alert time, as median and 10th percentile |
| Latency | Audio frame time to spoken alert onset, measured on device |
| Per-condition breakdown | All of the above by speed band, wind, mount, route and vehicle type |

Set the acceptance thresholds with the team **before** evaluation. Suggested starting points for
discussion: no more than 1 false alert per hour, a 10th-percentile lead time of at least 3 s, and
missed events reported with confidence intervals. These are not commitments.

## Step 5: If the built-in classifier fails

- Train a custom classifier (Create ML Sound Classifier or a Core ML conversion) on the
  collected dataset. Check the license of every external dataset before use and record it in this
  file.
- Consider wind-noise mitigation: microphone placement, a foam windscreen, or using the
  `wind_noise_microphone` label to report *degraded monitoring* rather than to suppress alerts.
- Re-run the same evaluation protocol on the same held-out sets.

## Step 6: Integration (only after acceptance)

- Implement `DetectionProvider` with `SNAudioStreamAnalyzer` fed from `MicrophoneCapture` buffers.
- Set `lastInputAt` for every analysed window, so stale or blocked input shows as degraded
  monitoring.
- Emit only `possibleVehicleSound`. Keep the experimental label in the UI and in speech until a
  wider validation is done.
- Keep sensing and group voice as separate modes until they are tested together on hardware.
