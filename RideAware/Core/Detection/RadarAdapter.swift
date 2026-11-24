import Foundation

/// Connection state of an external radar adapter.
enum RadarConnectionState: String, Sendable {
    case simulated
    case disconnected
    case scanning
    case connected
}

/// Boundary for a future external cycling radar.
///
/// No real radar device is supported. Before adding one, follow
/// docs/RADAR_INTEGRATION_CHECKLIST.md: verify the specific device's Bluetooth protocol from a
/// documented source, confirm SDK and licensing terms, and test with the hardware. Do not add
/// service or characteristic UUIDs without a cited source, and do not assume all radars share a
/// protocol. Range, direction or closing-speed fields may only be surfaced from a device whose
/// output format is documented and has been validated.
@MainActor
protocol RadarAdapter: DetectionProvider {
    var connectionState: RadarConnectionState { get }
    /// Name of the connected device, if any.
    var deviceName: String? { get }
}

/// Clearly labelled radar simulator. Emits `simulatedRadarTarget` events with no range,
/// direction or speed information.
@MainActor
final class SimulatedRadarAdapter: RadarAdapter {
    let descriptor = DetectorDescriptor(
        kind: .radarAdapter,
        name: "Radar simulator",
        isSimulated: true,
        summary: "Simulated radar targets. No radar hardware is supported in this build."
    )
    let availability: DetectorAvailability = .ready
    let connectionState: RadarConnectionState = .simulated
    let deviceName: String? = nil
    private(set) var isRunning = false
    private(set) var lastInputAt: Date?
    private(set) var failureReason: String?
    var onEvent: (@MainActor (DetectionEvent) -> Void)?

    /// Seconds between simulated targets.
    let targetInterval: TimeInterval
    private let now: () -> Date
    private var startedAt: Date?
    private var targetsEmitted = 0
    private var ticker: Task<Void, Never>?

    init(targetInterval: TimeInterval = 20, now: @escaping () -> Date = Date.init) {
        self.targetInterval = targetInterval
        self.now = now
    }

    func start() {
        stop()
        let date = now()
        isRunning = true
        startedAt = date
        lastInputAt = date
        targetsEmitted = 0
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                self.advance(to: self.now())
            }
        }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        isRunning = false
    }

    func advance(to date: Date) {
        guard isRunning, let startedAt else { return }
        lastInputAt = date
        let due = Int(date.timeIntervalSince(startedAt) / targetInterval)
        while targetsEmitted < due {
            targetsEmitted += 1
            let observedAt = startedAt.addingTimeInterval(Double(targetsEmitted) * targetInterval)
            onEvent?(DetectionEvent(
                kind: .simulatedRadarTarget,
                source: .radarSimulator,
                sourceTimestamp: observedAt,
                receivedAt: date,
                correlationID: "sim-track-\(targetsEmitted)"
            ))
        }
    }
}
