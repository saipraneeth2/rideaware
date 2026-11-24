import Foundation
import Testing
@testable import RideAware

@MainActor
final class RideHarness {
    let clock = TestClock()
    let speaker = FakeSpeaker()
    let microphone = FakeMicrophone()
    let detector = FakeDetector()
    let store = InMemoryRideStore()
    let location = FakeLocationProvider()
    let alerts: AlertCoordinator
    let history: RideHistory
    let group: GroupSession
    let sharing: LocationSharingController
    let ride: RideController

    init(transportAvailable: Bool = true) {
        alerts = AlertCoordinator(speaker: speaker, now: clock.closure)
        history = RideHistory(store: store)
        group = GroupSession(localRider: RiderIdentity(id: UUID(), displayName: "Me"), now: clock.closure)
        sharing = LocationSharingController(provider: location, transportAvailable: transportAvailable)
        // Same wiring as AppEnvironment.
        group.onJoin = { [sharing] in sharing.groupDidJoin() }
        group.onLeave = { [sharing] in sharing.groupDidLeave() }
        let detector = self.detector
        ride = RideController(microphone: microphone, alerts: alerts, history: history,
                              locationSharing: sharing, group: group,
                              makeDetector: { _ in detector }, now: clock.closure)
    }

    func start(microphone: Bool = true) async {
        await ride.start(RideConfiguration(detector: .simulation(.silence), microphoneEnabled: microphone,
                                           microphonePreference: .automatic), runTicker: false)
    }

    /// Simulates healthy detector input at the current time and ticks.
    func healthyTick(after seconds: TimeInterval) {
        clock.advance(seconds)
        detector.lastInputAt = clock.now
        ride.tick(at: clock.now)
    }
}

@MainActor
@Suite("Ride lifecycle")
struct RideLifecycleTests {
    @Test func startRunsMicrophoneAndDetectorAndAnnouncesSimulation() async {
        let h = RideHarness()
        await h.start()
        #expect(h.ride.isRiding)
        #expect(h.microphone.startCount == 1)
        #expect(h.detector.isRunning)
        #expect(h.speaker.spoken.last == .rideStarted(.simulation))
        #expect(h.ride.monitoring.detector == .starting)
    }

    @Test func stopShutsDownEverythingAndPersistsTheSession() async throws {
        let h = RideHarness()
        await h.start()
        h.healthyTick(after: 1)
        h.detector.emit(makeEvent(source: .simulation(scenario: .silence), observedAt: h.clock.now))
        h.clock.advance(60)
        h.ride.stop()

        #expect(!h.ride.isRiding)
        #expect(h.microphone.stopCount == 1)
        #expect(!h.detector.isRunning)
        #expect(h.detector.onEvent == nil)
        #expect(h.ride.monitoring == .idle)
        #expect(h.history.rides.count == 1)
        let saved = h.history.rides[0]
        #expect(saved.duration == 61)
        #expect(saved.detectorIsSimulated)
        #expect(saved.counts.announced == 1)
        #expect(try h.store.load().count == 1)
        #expect(h.speaker.spoken.last == .rideEnded)
    }

    @Test func eventsAfterStopAreNotHandled() async {
        let h = RideHarness()
        await h.start()
        let callback = h.detector.onEvent
        h.ride.stop()
        callback?(makeEvent(observedAt: h.clock.now))
        // The coordinator was reset for the ride; the stored ride has no announcements.
        #expect(h.history.rides[0].counts.announced == 0)
    }

    @Test func secondStartWhileRidingIsIgnored() async {
        let h = RideHarness()
        await h.start()
        await h.start()
        #expect(h.microphone.startCount == 1)
        #expect(h.detector.startCount == 1)
    }

    @Test func unavailableDetectorStartsRideButSaysDetectionUnavailable() async {
        let h = RideHarness()
        h.detector.descriptor = DetectorDescriptor(kind: .experimentalAcoustic, name: "Acoustic", isSimulated: false, summary: "")
        h.detector.availability = .unavailable(reason: "No validated model")
        await h.start()
        #expect(h.speaker.spoken.last == .rideStarted(.detectionUnavailable))
        #expect(h.ride.monitoring.detector == .unavailable(reason: "No validated model"))
        #expect(!h.ride.monitoring.isMonitoringActive)
    }

    @Test func deniedMicrophoneIsReportedAndRideContinues() async {
        let h = RideHarness()
        h.microphone.healthWhenStarted = .unavailable(reason: "Microphone permission denied")
        await h.start()
        h.healthyTick(after: 1)
        #expect(h.ride.isRiding)
        #expect(h.ride.monitoring.microphone == .unavailable(reason: "Microphone permission denied"))
        // The simulated detector does not depend on the microphone.
        #expect(h.ride.monitoring.isMonitoringActive)
    }

    @Test func sensorFailureIsSurfacedSpokenAndRecorded() async {
        let h = RideHarness()
        await h.start()
        h.healthyTick(after: 1)
        #expect(h.ride.monitoring.isMonitoringActive)

        h.detector.failureReason = "Sensor failed"
        h.detector.isRunning = false
        h.clock.advance(1)
        h.ride.tick(at: h.clock.now)

        #expect(h.ride.monitoring.detector == .failed(reason: "Sensor failed"))
        #expect(h.speaker.spoken.last == .monitoringStopped(reason: "Sensor failed"))
        #expect(h.ride.activeRide?.healthIncidents.last?.summary == "Monitoring stopped: Sensor failed")
    }

    @Test func staleDetectorInputIsSurfaced() async {
        let h = RideHarness()
        await h.start()
        h.healthyTick(after: 1)
        h.clock.advance(5)
        h.ride.tick(at: h.clock.now)
        #expect(h.ride.monitoring.detector == .stale(lastInputAge: 5))
        #expect(h.speaker.spoken.last == .monitoringStopped(reason: "Detector input is stale"))
    }
}

@MainActor
@Suite("Location sharing is opt-in, scoped to the group ride, and stops immediately")
struct LocationSharingTests {
    @Test func offByDefault() async throws {
        let h = RideHarness()
        try h.group.createGroup(name: "Ride")
        await h.start()
        #expect(!h.location.isUpdating)
        #expect(!h.sharing.isSharing)
    }

    @Test func optInOnlySharesDuringActiveGroupRide() async throws {
        let h = RideHarness()
        h.sharing.setOptedIn(true)
        #expect(!h.location.isUpdating) // no ride, no group
        try h.group.createGroup(name: "Ride")
        #expect(!h.location.isUpdating) // no ride yet
        await h.start()
        #expect(h.location.isUpdating)
        #expect(h.sharing.isSharing)
    }

    @Test func endingRideStopsSharingAndClearsOptIn() async throws {
        let h = RideHarness()
        try h.group.createGroup(name: "Ride")
        await h.start()
        h.sharing.setOptedIn(true)
        h.healthyTick(after: 1)
        #expect(h.location.isUpdating)

        h.ride.stop()
        #expect(!h.location.isUpdating)
        #expect(h.location.stopCount == 1)
        #expect(!h.sharing.optedIn)
        #expect(h.history.rides[0].locationSharingUsed)

        // A new ride does not silently resume sharing.
        await h.start()
        #expect(!h.location.isUpdating)
    }

    @Test func leavingGroupStopsSharingImmediatelyMidRide() async throws {
        let h = RideHarness()
        try h.group.createGroup(name: "Ride")
        await h.start()
        h.sharing.setOptedIn(true)
        #expect(h.location.isUpdating)

        h.group.leave()
        #expect(!h.location.isUpdating)
        #expect(h.ride.isRiding)
        #expect(!h.sharing.optedIn)
    }

    @Test func optingOutStopsSharingImmediately() async throws {
        let h = RideHarness()
        try h.group.createGroup(name: "Ride")
        await h.start()
        h.sharing.setOptedIn(true)
        h.sharing.setOptedIn(false)
        #expect(!h.location.isUpdating)
    }

    @Test func neverSharesWithoutTransport() async throws {
        let h = RideHarness(transportAvailable: false)
        try h.group.createGroup(name: "Ride")
        await h.start()
        h.sharing.setOptedIn(true)
        #expect(!h.location.isUpdating)
        #expect(!h.sharing.optedIn)
        #expect(h.sharing.unavailableReason != nil)
    }
}
