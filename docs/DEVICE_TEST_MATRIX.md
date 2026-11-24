# Physical-device test matrix

None of these rows has been run. The simulator cannot answer them. Record every run with the
device model, iOS version, AirPods model and firmware, app build, date, location type and weather.
Start in controlled environments (a parked bike, a closed lot, recorded playback) before any
public-road observation, and do not treat road use as evidence of reliability.

**Result codes:** P = pass, F = fail, N/A = not applicable to this configuration, ? = not yet run.

## A. Audio routing and capture

| # | Input | Output | Check | Expected / record | Result |
|-|-|-|-|-|-|
| A1 | iPhone mic (Automatic) | iPhone speaker | Ride start, mic health Live, format shown | Format and sample rate in Diagnostics | ? |
| A2 | iPhone mic (Automatic) | AirPods (A2DP) | Mic stays iPhone, output AirPods, music quality unchanged | Route rows; subjective music quality | ? |
| A3 | AirPods mic (HFP) | AirPods (HFP) | Input switches to AirPods; note music degradation | Input sample rate (expect narrow-band) | ? |
| A4 | AirPods high quality | AirPods | `highQualityRecording` Supported/Enabled per model | Status string, sample rate, input latency | ? |
| A5 | AirPods high quality on unsupported AirPods | AirPods | Falls back to HFP; mismatch or "not supported" shown | Status string | ? |
| A6 | System microphone picker | any | Chosen input becomes active and Diagnostics updates | Route after choice | ? |
| A7 | Wired or USB-C headset | headset | Route recognised, mic captured | Route rows | ? |
| A8 | Each of A1–A5 | | Spoken test prompt audible on expected output | Latency from tap to sound | ? |

## B. Interruptions and failures

| # | Scenario | Expected behaviour | Result |
|-|-|-|-|
| B1 | AirPods removed or powered off mid-ride | "Headphones disconnected" incident; speech uses the speaker only if fallback is on; capture restarts | ? |
| B2 | AirPods reconnect mid-ride | Route updates; capture restarts; no crash | ? |
| B3 | Incoming phone call (answer, then hang up) | Mic health Interrupted; after the call, capture resumes and "Monitoring resumed" is spoken if it had stopped | ? |
| B4 | Incoming call declined | Same as B3 without a long interruption | ? |
| B5 | Siri invoked | Interruption handled | ? |
| B6 | Another app takes non-mixable audio | Interruption reported; resume attempted | ? |
| B7 | Mic permission denied in Settings, then ride started | "Unavailable: permission denied"; ride runs; no crash | ? |
| B8 | Media services reset (Settings › Developer › Reset Media Services, if present) | Session reapplied; capture restarts | ? |
| B9 | iOS 26.x device versus iOS 27.x device | Interruption handling via legacy versus new notifications | ? |

## C. Background and lock screen

| # | Scenario | Expected / record | Result |
|-|-|-|-|
| C1 | Lock the screen during a ride with the mic on | Capture continues (buffers keep increasing); spoken simulated alerts still play | ? |
| C2 | Lock the screen in simulation with the mic off | Expected: app suspends between prompts. Confirm and document | ? |
| C3 | Switch to Maps or Music during a ride | Capture continues; music mixes with alerts | ? |
| C4 | 60-minute locked ride | No silent stop; health incidents logged | ? |

## D. Acoustic conditions (feasibility data, not detection claims)

Record 15 s consented samples for each condition. Note the microphone position (pocket, bar mount, AirPods).

| # | Condition | Record | Result |
|-|-|-|-|
| D1 | Stationary, quiet | Noise floor dBFS per input | ? |
| D2 | Riding at 15, 25 and 35 km/h, no traffic | Wind noise level per input and mount | ? |
| D3 | Mic covered by a jersey pocket or bag | Level drop | ? |
| D4 | Rider speech | Level and spectrum notes | ? |
| D5 | Music playing through AirPods | Bleed into the iPhone mic | ? |
| D6 | Combustion car approaching from behind (controlled) | Onset time versus pass time | ? |
| D7 | Electric vehicle approaching at low speed (controlled) | Onset time versus pass time | ? |
| D8 | Truck or bus | Same | ? |

## E. Network (Milestone 3)

| # | Scenario | Expected | Result |
|-|-|-|-|
| E1 | Network lost mid-group-ride | Presence turns stale; reports queue or fail visibly | N/A (no transport) |
| E2 | Reconnect | Presence recovers; no duplicate reports | N/A |
| E3 | Leave group with sharing on | Location stops immediately on device and server | N/A |

## F. Battery and latency

| # | Measure | Method | Result |
|-|-|-|-|
| F1 | Battery per hour with mic on, simulation | Start/end battery %, Instruments Energy Log | ? |
| F2 | Battery per hour with the AirPods HQ route | Same | ? |
| F3 | Alert latency: event to first audible sound | Screen and audio recording, or instrumented log | ? |
| F4 | Capture restart time after a route change | Diagnostics "last buffer" gap | ? |
