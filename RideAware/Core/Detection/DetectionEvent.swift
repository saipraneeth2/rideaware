import Foundation

/// What a detector claims to have observed.
///
/// Labels are deliberately conservative. None of them carries direction, distance or
/// closing speed: those may only be introduced for a source whose measurements have been
/// independently validated (see docs/RADAR_INTEGRATION_CHECKLIST.md).
enum DetectionKind: String, Codable, Sendable, CaseIterable, Hashable {
    /// Experimental acoustic inference, or a simulation of it.
    case possibleVehicleSound
    /// Output of the radar *simulator*. No real radar device is supported yet.
    case simulatedRadarTarget

    var displayLabel: String {
        switch self {
        case .possibleVehicleSound: "Possible vehicle sound"
        case .simulatedRadarTarget: "Radar target (simulator)"
        }
    }
}

/// Where a detection came from. A report from another rider is never a `DetectionSource`;
/// see `GroupReport`, which is kept in a separate feed.
enum DetectionSource: Codable, Sendable, Hashable {
    case simulation(scenario: SimulationScenario)
    case experimentalAcoustic(modelName: String)
    case radarSimulator

    var isSimulated: Bool {
        switch self {
        case .simulation, .radarSimulator: true
        case .experimentalAcoustic: false
        }
    }

    var displayName: String {
        switch self {
        case .simulation(let scenario): "Simulation (\(scenario.title.lowercased()))"
        case .experimentalAcoustic(let modelName): "Experimental acoustic model: \(modelName)"
        case .radarSimulator: "Radar simulator"
        }
    }

    /// Stable category used for de-duplication keys.
    var category: String {
        switch self {
        case .simulation: "simulation"
        case .experimentalAcoustic: "acoustic"
        case .radarSimulator: "radar-sim"
        }
    }
}

/// One observation from a detector, carrying the time the *sensor* observed it.
struct DetectionEvent: Identifiable, Sendable, Equatable, Codable {
    let id: UUID
    let kind: DetectionKind
    let source: DetectionSource
    /// When the sensor observed the signal (this device's clock).
    let sourceTimestamp: Date
    /// When the app received the event.
    let receivedAt: Date
    /// Groups events that describe the same underlying observation, such as one continuous sound
    /// or one radar track. `nil` means "no tracking information".
    let correlationID: String?
    /// Raw, uncalibrated detector output for diagnostics only.
    /// It is not a probability and must never be shown as one, or as a measure of safety.
    let rawScore: Double?

    init(
        id: UUID = UUID(),
        kind: DetectionKind,
        source: DetectionSource,
        sourceTimestamp: Date,
        receivedAt: Date,
        correlationID: String? = nil,
        rawScore: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.sourceTimestamp = sourceTimestamp
        self.receivedAt = receivedAt
        self.correlationID = correlationID
        self.rawScore = rawScore
    }

    /// Events with the same key are treated as the same observation for de-duplication.
    var dedupKey: String {
        "\(source.category)|\(kind.rawValue)|\(correlationID ?? "-")"
    }

    /// Age relative to the sensor's observation time.
    func age(at now: Date) -> TimeInterval {
        now.timeIntervalSince(sourceTimestamp)
    }
}
