import Foundation
import Testing
@testable import RideAware

@Suite("Alert de-duplication, cooldown and stale rejection")
struct AlertGateTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let policy = AlertPolicy(maxEventAge: 2, maxFutureSkew: 0.5, dedupWindow: 4, cooldown: 10)

    @Test func firstFreshEventIsAnnounced() {
        var gate = AlertGate(policy: policy)
        #expect(gate.evaluate(makeEvent(observedAt: t0, correlationID: "a"), now: t0) == .announce)
    }

    @Test func sameObservationWithinWindowIsDuplicate() {
        var gate = AlertGate(policy: policy)
        _ = gate.evaluate(makeEvent(observedAt: t0, correlationID: "a"), now: t0)
        let later = t0.addingTimeInterval(1)
        #expect(gate.evaluate(makeEvent(observedAt: later, correlationID: "a"), now: later) == .duplicate)
    }

    @Test func continuousSoundProducesExactlyOneAlert() {
        var gate = AlertGate(policy: policy)
        var announced = 0
        // One sound reported every 0.5 s for 30 s: longer than both window and cooldown.
        for i in 0...60 {
            let t = t0.addingTimeInterval(Double(i) * 0.5)
            if gate.evaluate(makeEvent(observedAt: t, correlationID: "continuous"), now: t) == .announce {
                announced += 1
            }
        }
        #expect(announced == 1)
    }

    @Test func differentObservationInsideCooldownIsSuppressed() {
        var gate = AlertGate(policy: policy)
        _ = gate.evaluate(makeEvent(observedAt: t0, correlationID: "a"), now: t0)
        let t = t0.addingTimeInterval(6)
        let decision = gate.evaluate(makeEvent(observedAt: t, correlationID: "b"), now: t)
        #expect(decision == .coolingDown(remaining: 4))
    }

    @Test func newObservationAfterCooldownIsAnnounced() {
        var gate = AlertGate(policy: policy)
        _ = gate.evaluate(makeEvent(observedAt: t0, correlationID: "a"), now: t0)
        let t = t0.addingTimeInterval(10)
        #expect(gate.evaluate(makeEvent(observedAt: t, correlationID: "b"), now: t) == .announce)
    }

    @Test func sameObservationAfterGapLongerThanWindowCountsAsNew() {
        var gate = AlertGate(policy: policy)
        _ = gate.evaluate(makeEvent(observedAt: t0, correlationID: "a"), now: t0)
        let t = t0.addingTimeInterval(12)
        #expect(gate.evaluate(makeEvent(observedAt: t, correlationID: "a"), now: t) == .announce)
    }

    @Test func cooldownIsPerKind() {
        var gate = AlertGate(policy: policy)
        _ = gate.evaluate(makeEvent(kind: .possibleVehicleSound, observedAt: t0, correlationID: "a"), now: t0)
        let t = t0.addingTimeInterval(1)
        let radar = makeEvent(kind: .simulatedRadarTarget, source: .radarSimulator, observedAt: t, correlationID: "r")
        #expect(gate.evaluate(radar, now: t) == .announce)
    }

    @Test func staleEventIsRejected() {
        var gate = AlertGate(policy: policy)
        let now = t0.addingTimeInterval(3)
        #expect(gate.evaluate(makeEvent(observedAt: t0, receivedAt: now), now: now) == .stale(age: 3))
    }

    @Test func eventExactlyAtMaxAgeIsAccepted() {
        var gate = AlertGate(policy: policy)
        let now = t0.addingTimeInterval(2)
        #expect(gate.evaluate(makeEvent(observedAt: t0), now: now) == .announce)
    }

    @Test func staleEventDoesNotConsumeCooldownOrDedupState() {
        var gate = AlertGate(policy: policy)
        let now = t0.addingTimeInterval(5)
        #expect(gate.evaluate(makeEvent(observedAt: t0, correlationID: "a"), now: now) == .stale(age: 5))
        #expect(gate.evaluate(makeEvent(observedAt: now, correlationID: "a"), now: now) == .announce)
    }

    @Test func futureTimestampIsRejected() {
        var gate = AlertGate(policy: policy)
        let decision = gate.evaluate(makeEvent(observedAt: t0.addingTimeInterval(1)), now: t0)
        #expect(decision == .futureTimestamp(skew: 1))
        #expect(decision.isRejection)
    }

    @Test func outOfOrderDuplicateIsStillDuplicate() {
        var gate = AlertGate(policy: policy)
        let t = t0.addingTimeInterval(1)
        _ = gate.evaluate(makeEvent(observedAt: t, correlationID: "a"), now: t)
        #expect(gate.evaluate(makeEvent(observedAt: t0.addingTimeInterval(0.5), correlationID: "a"), now: t) == .duplicate)
    }
}

@MainActor
@Suite("Alert coordinator")
struct AlertCoordinatorTests {
    @Test func announcedEventIsSpokenWithConservativeWording() {
        let clock = TestClock()
        let speaker = FakeSpeaker()
        let alerts = AlertCoordinator(speaker: speaker, now: clock.closure)
        alerts.handle(makeEvent(observedAt: clock.now, correlationID: "a"))
        #expect(speaker.spoken == [.detection(.possibleVehicleSound, simulated: false)])
        #expect(speaker.spoken.first?.text == "Possible vehicle sound.")
    }

    @Test func simulatedEventIsSpokenAsSimulation() {
        let clock = TestClock()
        let speaker = FakeSpeaker()
        let alerts = AlertCoordinator(speaker: speaker, now: clock.closure)
        alerts.handle(makeEvent(source: .simulation(scenario: .approachingTraffic), observedAt: clock.now))
        #expect(speaker.spoken.first?.text.hasPrefix("Simulation.") == true)
    }

    @Test func suppressedAndRejectedEventsAreLoggedButNotSpoken() {
        let clock = TestClock()
        let speaker = FakeSpeaker()
        let alerts = AlertCoordinator(speaker: speaker, now: clock.closure)
        alerts.handle(makeEvent(observedAt: clock.now, correlationID: "a"))
        clock.advance(1)
        alerts.handle(makeEvent(observedAt: clock.now, correlationID: "a"))
        alerts.handle(makeEvent(observedAt: clock.now.addingTimeInterval(-5), correlationID: "old"))
        #expect(speaker.spoken.count == 1)
        #expect(alerts.log.count == 3)
        #expect(alerts.counts == AlertCounts(announced: 1, duplicates: 1, cooldownSuppressed: 0, rejectedStale: 1, rejectedOther: 0))
    }

    @Test func speechCanBeDisabledWithoutLosingTheDecision() {
        let clock = TestClock()
        let speaker = FakeSpeaker()
        let alerts = AlertCoordinator(speaker: speaker, now: clock.closure)
        alerts.isSpeechAllowed = { _ in false }
        #expect(alerts.handle(makeEvent(observedAt: clock.now)) == .announce)
        #expect(speaker.spoken.isEmpty)
        #expect(alerts.lastAnnounced?.spoken == false)
    }

    @Test func resetClearsStateForNewRide() {
        let clock = TestClock()
        let alerts = AlertCoordinator(speaker: FakeSpeaker(), now: clock.closure)
        alerts.handle(makeEvent(observedAt: clock.now, correlationID: "a"))
        alerts.resetForNewRide()
        #expect(alerts.log.isEmpty)
        #expect(alerts.counts == AlertCounts())
        #expect(alerts.handle(makeEvent(observedAt: clock.now, correlationID: "a")) == .announce)
    }
}
