# External radar integration checklist

RideAware supports **no** radar device. `SimulatedRadarAdapter` exists only to exercise the
`RadarAdapter` boundary and the alert pipeline. Do not advertise compatibility until every
step below is complete for a **specific** device model.

## Before writing code

- [ ] Name the exact device model and firmware version.
- [ ] Find the manufacturer's **published** documentation of its Bluetooth LE protocol: services,
      characteristics, data format, units and update rate. Cite the document (URL, version, date) here.
- [ ] If the protocol is only available through an SDK, read the SDK license. Confirm that it
      permits use in this app (including distribution and any App Store terms) and record the
      decision.
- [ ] If the protocol is undocumented, stop. Do not reverse-engineer or guess UUIDs, and do not
      assume that radars from different vendors share a protocol.
- [ ] Confirm whether the device allows more than one central at a time (for example, a bike
      computer and a phone).

## Implementation

- [ ] Implement `RadarAdapter` for that one device, using CoreBluetooth with documented UUIDs
      only. Add `NSBluetoothAlwaysUsageDescription`.
- [ ] Map each documented target field to app types. Range, closing speed or threat level may be
      surfaced **only** if the documentation defines them and on-bike validation agrees.
- [ ] Set `lastInputAt` on every packet, including "no targets" packets, so silence from the
      sensor and a dead link can be told apart (stale input).
- [ ] Report connection loss as degraded monitoring and speak it. Never present it as "no traffic".
- [ ] Keep `DetectionSource` distinct (for example `.radar(deviceModel:)`) so radar alerts are
      attributed separately from acoustic ones.

## Validation with hardware

- [ ] Bench test: power cycle, out-of-range, reconnect, and battery-low behaviour.
- [ ] Controlled test with known vehicle passes: measure detection rate, false alerts per hour and
      lead time against ground truth (camera).
- [ ] Measure Bluetooth latency from radar packet to spoken alert.
- [ ] Test coexistence with AirPods audio and with the microphone sensing mode.
- [ ] Record results in DEVICE_TEST_MATRIX.md. Only then list the device as supported.
