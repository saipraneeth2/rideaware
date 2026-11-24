import Foundation
import Testing
@testable import RideAware

@Suite("Stream health: permission, interruption, stale and sensor failure states")
struct StreamHealthEvaluatorTests {
    let evaluator = StreamHealthEvaluator(staleAfter: 2, startupGrace: 3)
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func notRunningIsOff() {
        #expect(evaluator.evaluate(isRunning: false, startedAt: nil, lastInputAt: nil, now: t0) == .off)
    }

    @Test func startingWithinGraceThenStaleWithoutInput() {
        #expect(evaluator.evaluate(isRunning: true, startedAt: t0, lastInputAt: nil, now: t0.addingTimeInterval(2)) == .starting)
        #expect(evaluator.evaluate(isRunning: true, startedAt: t0, lastInputAt: nil, now: t0.addingTimeInterval(4)) == .stale(lastInputAge: nil))
    }

    @Test func freshInputIsLiveOldInputIsStale() {
        let input = t0.addingTimeInterval(1)
        #expect(evaluator.evaluate(isRunning: true, startedAt: t0, lastInputAt: input, now: t0.addingTimeInterval(2.5)).isLive)
        #expect(evaluator.evaluate(isRunning: true, startedAt: t0, lastInputAt: input, now: t0.addingTimeInterval(4)) == .stale(lastInputAge: 3))
    }

    @Test func inputFromBeforeRestartIsIgnored() {
        let restart = t0.addingTimeInterval(10)
        let health = evaluator.evaluate(isRunning: true, startedAt: restart, lastInputAt: t0, now: restart.addingTimeInterval(5))
        #expect(health == .stale(lastInputAge: nil))
    }

    @Test func deniedPermissionOutranksEverything() {
        let health = evaluator.evaluate(isRunning: false, startedAt: nil, lastInputAt: nil, now: t0,
                                        interruptedReason: "Call", unavailableReason: "Permission denied", failureReason: "x")
        #expect(health == .unavailable(reason: "Permission denied"))
        #expect(health.severity == .critical)
    }

    @Test func failureOutranksInterruption() {
        let health = evaluator.evaluate(isRunning: false, startedAt: nil, lastInputAt: nil, now: t0,
                                        interruptedReason: "Call", failureReason: "Sensor failed")
        #expect(health == .failed(reason: "Sensor failed"))
    }

    @Test func interruptionIsReportedEvenIfLastInputWasRecent() {
        let health = evaluator.evaluate(isRunning: true, startedAt: t0, lastInputAt: t0, now: t0,
                                        interruptedReason: "Phone call")
        #expect(health == .interrupted(reason: "Phone call"))
        #expect(!health.isLive)
    }
}

@Suite("Monitoring snapshot never claims safety")
struct MonitoringSnapshotTests {
    @Test func liveMicrophoneAloneIsNotMonitoring() {
        let snapshot = MonitoringSnapshot(isRiding: true, detector: .unavailable(reason: "No model"),
                                          detectorName: "Acoustic", detectorIsSimulated: false,
                                          microphone: .live(lastInputAge: 0))
        #expect(!snapshot.isMonitoringActive)
        #expect(snapshot.headline == "Not monitoring for vehicles")
        #expect(snapshot.inactiveReason == "No model")
    }

    @Test func simulatedDetectorIsLabelledSimulated() {
        let snapshot = MonitoringSnapshot(isRiding: true, detector: .live(lastInputAge: 0),
                                          detectorName: "Sim", detectorIsSimulated: true, microphone: .off)
        #expect(snapshot.headline == "Simulated monitoring active")
    }

    @Test func headlinesContainNoSafetyClaims() {
        let detectors: [StreamHealth] = [.off, .starting, .live(lastInputAge: 0), .stale(lastInputAge: nil),
                                         .interrupted(reason: "x"), .unavailable(reason: "x"), .failed(reason: "x")]
        for detector in detectors {
            for simulated in [true, false] {
                let headline = MonitoringSnapshot(isRiding: true, detector: detector, detectorName: "d",
                                                  detectorIsSimulated: simulated, microphone: .off).headline.lowercased()
                #expect(!headline.contains("safe"))
                #expect(!headline.contains("clear"))
            }
        }
    }
}

@Suite("Spoken health announcements")
struct HealthAnnouncerTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func snapshot(_ detector: StreamHealth) -> MonitoringSnapshot {
        MonitoringSnapshot(isRiding: true, detector: detector, detectorName: "d", detectorIsSimulated: false, microphone: .off)
    }

    @Test func baselineIsNotAnnounced() {
        var announcer = HealthAnnouncer()
        #expect(announcer.update(snapshot(.live(lastInputAge: 0)), now: t0) == nil)
    }

    @Test func lossOfMonitoringIsAnnouncedWithReason() {
        var announcer = HealthAnnouncer()
        _ = announcer.update(snapshot(.live(lastInputAge: 0)), now: t0)
        let phrase = announcer.update(snapshot(.failed(reason: "Sensor failed")), now: t0.addingTimeInterval(1))
        #expect(phrase == .monitoringStopped(reason: "Sensor failed"))
    }

    @Test func briefFlapInsideIntervalIsNotRepeated() {
        var announcer = HealthAnnouncer(minimumInterval: 10)
        _ = announcer.update(snapshot(.live(lastInputAge: 0)), now: t0)
        #expect(announcer.update(snapshot(.stale(lastInputAge: 4)), now: t0.addingTimeInterval(1)) == .monitoringStopped(reason: "Detector input is stale"))
        // Recovers 2 s later: inside the interval, so not yet spoken.
        #expect(announcer.update(snapshot(.live(lastInputAge: 0)), now: t0.addingTimeInterval(3)) == nil)
        // Fails again before the interval: still matches the announced (stopped) state.
        #expect(announcer.update(snapshot(.stale(lastInputAge: 4)), now: t0.addingTimeInterval(5)) == nil)
    }

    @Test func persistentRecoveryIsAnnouncedAfterInterval() {
        var announcer = HealthAnnouncer(minimumInterval: 10)
        _ = announcer.update(snapshot(.live(lastInputAge: 0)), now: t0)
        _ = announcer.update(snapshot(.stale(lastInputAge: 4)), now: t0.addingTimeInterval(1))
        #expect(announcer.update(snapshot(.live(lastInputAge: 0)), now: t0.addingTimeInterval(3)) == nil)
        #expect(announcer.update(snapshot(.live(lastInputAge: 0)), now: t0.addingTimeInterval(12)) == .monitoringResumed)
    }

    @Test func startingStateIsIgnored() {
        var announcer = HealthAnnouncer()
        #expect(announcer.update(snapshot(.starting), now: t0) == nil)
        #expect(announcer.update(snapshot(.live(lastInputAge: 0)), now: t0.addingTimeInterval(1)) == nil)
    }
}

@MainActor
@Suite("Microphone permission handling with the real MicrophoneMonitor")
struct MicrophonePermissionTests {
    func makeMonitor(_ permission: FakePermission) -> (MicrophoneMonitor, AudioSessionCoordinator) {
        let coordinator = AudioSessionCoordinator(microphonePreference: .automatic, duckOthersForPrompts: false)
        return (MicrophoneMonitor(coordinator: coordinator, permissions: permission), coordinator)
    }

    @Test func deniedPermissionMakesMicrophoneUnavailableWithoutTouchingSession() async {
        let permission = FakePermission(state: .denied)
        let (monitor, coordinator) = makeMonitor(permission)
        await monitor.start()
        #expect(!monitor.isRunning)
        #expect(monitor.permission == .denied)
        #expect(permission.requestCount == 0)
        if case .unavailable(let reason) = monitor.health {
            #expect(reason.contains("permission"))
        } else {
            Issue.record("Expected unavailable health, got \(monitor.health)")
        }
        #expect(!coordinator.activeDemands.contains(.microphoneSensing))
    }

    @Test func undeterminedPermissionIsRequestedOnceAndDenialIsReported() async {
        let permission = FakePermission(state: .undetermined, grantOnRequest: false)
        let (monitor, _) = makeMonitor(permission)
        await monitor.start()
        #expect(permission.requestCount == 1)
        #expect(monitor.permission == .denied)
        #expect(monitor.health.severity == .critical)
    }

    @Test func stoppingClearsUnavailableState() async {
        let (monitor, _) = makeMonitor(FakePermission(state: .denied))
        await monitor.start()
        monitor.stop()
        #expect(monitor.health == .off)
    }
}
