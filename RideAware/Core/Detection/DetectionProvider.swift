import Foundation

/// Family of detector implementations. Each is a separate type behind `DetectionProvider`.
enum DetectorKind: String, Sendable {
    case simulated
    case experimentalAcoustic
    case radarAdapter
}

struct DetectorDescriptor: Sendable, Equatable {
    let kind: DetectorKind
    let name: String
    let isSimulated: Bool
    /// One-sentence, user-facing description of what this detector can and cannot do.
    let summary: String
}

/// Whether a provider can run at all in this build and on this device.
enum DetectorAvailability: Equatable, Sendable {
    case ready
    case unavailable(reason: String)

    var unavailableReason: String? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

/// Which detector a ride uses.
enum DetectorChoice: Equatable, Sendable {
    case experimentalAcoustic
    case simulation(SimulationScenario)
    case radarSimulator
}

/// Common boundary for every detector: simulated events, experimental acoustic inference and
/// (future) external radar. Providers report events and their own input freshness; health is
/// evaluated by `StreamHealthEvaluator` so all providers are judged by the same rules.
@MainActor
protocol DetectionProvider: AnyObject {
    var descriptor: DetectorDescriptor { get }
    var availability: DetectorAvailability { get }
    /// `true` between `start()` and `stop()`, unless the provider failed.
    var isRunning: Bool { get }
    /// When the provider last processed input: an audio frame, a radar packet, or a simulated
    /// heartbeat. Used to detect stale input.
    var lastInputAt: Date? { get }
    /// Set when the provider has stopped producing events because of a fault.
    var failureReason: String? { get }
    var onEvent: (@MainActor (DetectionEvent) -> Void)? { get set }
    func start()
    func stop()
}
