import Foundation
import Testing
@testable import RideAware

/// Runs simulation scripts against the real alert gate and health evaluator.
@MainActor
@Suite("Simulation scenarios")
struct SimulationScenarioTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    struct Run {
        var decisions: [AlertDecision] = []
        var health: [TimeInterval: StreamHealth] = [:]
        var announced: Int { decisions.filter { $0 == .announce }.count }
        var duplicates: Int { decisions.filter { $0 == .duplicate }.count }
        var cooldown: Int { decisions.filter { if case .coolingDown = $0 { true } else { false } }.count }
        var stale: Int { decisions.filter { if case .stale = $0 { true } else { false } }.count }
    }

    func run(_ scenario: SimulationScenario, seconds: TimeInterval, sampleHealthAt: [TimeInterval] = []) -> Run {
        let provider = SimulatedDetectionProvider(scenario: scenario)
        var gate = AlertGate()
        let evaluator = StreamHealthEvaluator(staleAfter: 3, startupGrace: 4)
        var result = Run()
        var currentTime = t0
        provider.onEvent = { event in
            #expect(event.source.isSimulated)
            result.decisions.append(gate.evaluate(event, now: currentTime))
        }
        provider.start(at: t0, runClock: false)
        let steps = Int(seconds / 0.25)
        for i in 1...steps {
            let elapsed = Double(i) * 0.25
            currentTime = t0.addingTimeInterval(elapsed)
            provider.advance(to: currentTime)
            if sampleHealthAt.contains(elapsed) {
                result.health[elapsed] = evaluator.evaluate(
                    isRunning: provider.isRunning, startedAt: t0, lastInputAt: provider.lastInputAt,
                    now: currentTime, failureReason: provider.failureReason)
            }
        }
        return result
    }

    @Test func approachingTrafficYieldsOneAlertPerApproach() {
        let result = run(.approachingTraffic, seconds: 44)
        #expect(result.announced == 2)
        #expect(result.duplicates == 8)
    }

    @Test func approachingTrafficLoopsWithFreshCorrelationIDs() {
        let result = run(.approachingTraffic, seconds: 89)
        #expect(result.announced == 4)
    }

    @Test func repeatedDetectionsExerciseDedupAndCooldown() {
        let result = run(.repeatedDetections, seconds: 20)
        #expect(result.announced == 2)   // burst-1 at 4 s, third-sound at 16 s
        #expect(result.duplicates == 7)  // rest of burst-1
        #expect(result.cooldown == 1)    // second-sound at 9 s
    }

    @Test func silenceProducesNoEventsAndStaysLive() {
        let result = run(.silence, seconds: 60, sampleHealthAt: [10, 59])
        #expect(result.decisions.isEmpty)
        #expect(result.health[10]?.isLive == true)
        #expect(result.health[59]?.isLive == true)
    }

    @Test func sensorFailureGoesStaleThenFailed() {
        let result = run(.sensorFailure, seconds: 16, sampleHealthAt: [7, 12, 15])
        #expect(result.health[7]?.isLive == true)
        // Heartbeat stops at 8.0 s, so the last input was the 7.75 s tick.
        #expect(result.health[12] == .stale(lastInputAge: 4.25))
        #expect(result.health[15] == .failed(reason: "Simulated sensor failure"))
        #expect(result.announced == 1)
    }

    @Test func staleInputIsRejected() {
        let result = run(.staleInput, seconds: 30)
        #expect(result.stale == 2)
        #expect(result.announced == 1)
    }

    @Test func radarSimulatorEmitsLabelledTargetsWithoutRange() {
        let clock = TestClock(t0)
        let radar = SimulatedRadarAdapter(targetInterval: 20, now: clock.closure)
        var events: [DetectionEvent] = []
        radar.onEvent = { events.append($0) }
        radar.start()
        radar.advance(to: t0.addingTimeInterval(41))
        radar.stop()
        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.kind == .simulatedRadarTarget && $0.source.isSimulated })
        #expect(radar.descriptor.isSimulated)
    }

    @Test func acousticProviderIsHonestlyUnavailable() {
        let provider = ExperimentalAcousticProvider()
        var emitted = false
        provider.onEvent = { _ in emitted = true }
        provider.start()
        #expect(provider.availability == .unavailable(reason: ExperimentalAcousticProvider.unavailableReason))
        #expect(!provider.isRunning)
        #expect(!emitted)
    }
}
