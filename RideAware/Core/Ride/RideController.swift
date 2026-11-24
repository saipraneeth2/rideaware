import Foundation
import Observation

struct RideConfiguration: Sendable, Equatable {
    var detector: DetectorChoice
    var microphoneEnabled: Bool
    var microphonePreference: MicrophonePreference
}

/// Ride lifecycle: starts and stops the microphone, detector and location-sharing policy
/// together, evaluates monitoring health, announces health changes, and stores the session.
@MainActor
@Observable
final class RideController {
    private(set) var activeRide: RideSession?
    private(set) var monitoring = MonitoringSnapshot.idle
    private(set) var detectorDescriptor: DetectorDescriptor?
    private(set) var detectorAvailability: DetectorAvailability = .ready

    var isRiding: Bool { activeRide != nil }

    @ObservationIgnored private var detector: (any DetectionProvider)?
    @ObservationIgnored private var detectorStartedAt: Date?
    @ObservationIgnored private var healthAnnouncer = HealthAnnouncer()
    @ObservationIgnored private var lastMonitoringActive: Bool?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private let microphone: any MicrophoneMonitoring
    @ObservationIgnored private let alerts: AlertCoordinator
    @ObservationIgnored private let history: RideHistory
    @ObservationIgnored private let locationSharing: LocationSharingController
    @ObservationIgnored private let group: GroupSession
    @ObservationIgnored private let makeDetector: @MainActor (DetectorChoice) -> any DetectionProvider
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored let detectorEvaluator = StreamHealthEvaluator(staleAfter: 3.0, startupGrace: 4.0)

    init(
        microphone: any MicrophoneMonitoring,
        alerts: AlertCoordinator,
        history: RideHistory,
        locationSharing: LocationSharingController,
        group: GroupSession,
        makeDetector: @escaping @MainActor (DetectorChoice) -> any DetectionProvider,
        now: @escaping () -> Date = Date.init
    ) {
        self.microphone = microphone
        self.alerts = alerts
        self.history = history
        self.locationSharing = locationSharing
        self.group = group
        self.makeDetector = makeDetector
        self.now = now
    }

    static func makeDefaultDetector(_ choice: DetectorChoice) -> any DetectionProvider {
        switch choice {
        case .experimentalAcoustic: ExperimentalAcousticProvider()
        case .simulation(let scenario): SimulatedDetectionProvider(scenario: scenario)
        case .radarSimulator: SimulatedRadarAdapter()
        }
    }

    /// Starts a ride. `runTicker` is false in tests, which call `tick(at:)` directly.
    func start(_ configuration: RideConfiguration, runTicker: Bool = true) async {
        guard activeRide == nil else { return }
        alerts.resetForNewRide()
        healthAnnouncer = HealthAnnouncer()
        lastMonitoringActive = nil

        let provider = makeDetector(configuration.detector)
        provider.onEvent = { [weak self] event in self?.alerts.handle(event) }
        detector = provider
        detectorDescriptor = provider.descriptor
        detectorAvailability = provider.availability

        let ride = RideSession(
            id: UUID(),
            startedAt: now(),
            detectorName: provider.descriptor.name,
            detectorIsSimulated: provider.descriptor.isSimulated,
            microphoneEnabled: configuration.microphoneEnabled,
            microphonePreference: configuration.microphonePreference,
            groupName: group.group?.name
        )
        activeRide = ride

        if configuration.microphoneEnabled {
            await microphone.start()
            // The rider may have stopped the ride while the permission prompt was showing.
            guard activeRide?.id == ride.id else { return }
        }

        provider.start()
        detectorStartedAt = now()
        locationSharing.rideDidStart()
        tick(at: now())

        let mode: AlertPhrase.RideStartMode =
            provider.descriptor.isSimulated ? .simulation
            : provider.availability == .ready ? .monitoring
            : .detectionUnavailable
        alerts.notify(.rideStarted(mode), category: .ride)

        if runTicker {
            ticker = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard let self else { return }
                    self.tick(at: self.now())
                }
            }
        }
    }

    func stop() {
        guard var ride = activeRide else { return }
        ticker?.cancel()
        ticker = nil
        detector?.stop()
        detector?.onEvent = nil
        microphone.stop()
        locationSharing.rideDidEnd()

        ride.endedAt = now()
        ride.counts = alerts.counts
        activeRide = nil
        detector = nil
        detectorStartedAt = nil
        monitoring = .idle
        history.record(ride)
        alerts.notify(.rideEnded, category: .ride)
    }

    func recordIncident(_ summary: String) {
        activeRide?.healthIncidents.append(HealthIncident(at: now(), summary: summary))
    }

    func tick(at date: Date) {
        guard activeRide != nil, let detector else { return }
        microphone.evaluateHealth(now: date)
        let detectorHealth = detectorEvaluator.evaluate(
            isRunning: detector.isRunning,
            startedAt: detectorStartedAt,
            lastInputAt: detector.lastInputAt,
            now: date,
            unavailableReason: detector.availability.unavailableReason,
            failureReason: detector.failureReason
        )
        monitoring = MonitoringSnapshot(
            isRiding: true,
            detector: detectorHealth,
            detectorName: detector.descriptor.name,
            detectorIsSimulated: detector.descriptor.isSimulated,
            microphone: microphone.health
        )

        if monitoring.detector != .starting {
            let active = monitoring.isMonitoringActive
            if let previous = lastMonitoringActive, previous != active {
                recordIncident(active ? "Monitoring resumed" : "Monitoring stopped: \(monitoring.inactiveReason)")
            }
            lastMonitoringActive = active
        }
        if locationSharing.isSharing {
            activeRide?.locationSharingUsed = true
        }
        if let phrase = healthAnnouncer.update(monitoring, now: date) {
            alerts.notify(phrase, category: .health)
        }
    }
}
