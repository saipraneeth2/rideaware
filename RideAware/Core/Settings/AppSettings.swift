import Foundation
import Observation

enum DistanceUnits: String, CaseIterable, Identifiable, Sendable {
    case metric
    case imperial

    var id: String { rawValue }
    var title: String { self == .metric ? "Metric (km)" : "Imperial (mi)" }
}

/// Rider preferences, persisted in `UserDefaults`.
@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarding) } }
    var spokenAlertsEnabled: Bool { didSet { defaults.set(spokenAlertsEnabled, forKey: Keys.spoken) } }
    var spokenHealthAlertsEnabled: Bool { didSet { defaults.set(spokenHealthAlertsEnabled, forKey: Keys.spokenHealth) } }
    var spokenGroupMessagesEnabled: Bool { didSet { defaults.set(spokenGroupMessagesEnabled, forKey: Keys.spokenGroup) } }
    var allowSpeakerFallback: Bool { didSet { defaults.set(allowSpeakerFallback, forKey: Keys.speakerFallback) } }
    var duckOthersForPrompts: Bool { didSet { defaults.set(duckOthersForPrompts, forKey: Keys.duck) } }
    var units: DistanceUnits { didSet { defaults.set(units.rawValue, forKey: Keys.units) } }
    var recordingConsent: Bool { didSet { defaults.set(recordingConsent, forKey: Keys.consent) } }
    var microphoneEnabled: Bool { didSet { defaults.set(microphoneEnabled, forKey: Keys.microphone) } }
    var microphonePreference: MicrophonePreference { didSet { defaults.set(microphonePreference.rawValue, forKey: Keys.micPreference) } }
    var simulationModeEnabled: Bool { didSet { defaults.set(simulationModeEnabled, forKey: Keys.simulation) } }
    var simulationScenario: SimulationScenario { didSet { defaults.set(simulationScenario.rawValue, forKey: Keys.scenario) } }
    var useRadarSimulator: Bool { didSet { defaults.set(useRadarSimulator, forKey: Keys.radarSim) } }
    var riderDisplayName: String { didSet { defaults.set(riderDisplayName, forKey: Keys.riderName) } }
    let riderID: UUID

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.spoken: true,
            Keys.spokenHealth: true,
            Keys.spokenGroup: true,
            Keys.speakerFallback: true,
            Keys.duck: true,
            Keys.microphone: true,
        ])
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        spokenAlertsEnabled = defaults.bool(forKey: Keys.spoken)
        spokenHealthAlertsEnabled = defaults.bool(forKey: Keys.spokenHealth)
        spokenGroupMessagesEnabled = defaults.bool(forKey: Keys.spokenGroup)
        allowSpeakerFallback = defaults.bool(forKey: Keys.speakerFallback)
        duckOthersForPrompts = defaults.bool(forKey: Keys.duck)
        units = DistanceUnits(rawValue: defaults.string(forKey: Keys.units) ?? "") ?? .metric
        recordingConsent = defaults.bool(forKey: Keys.consent)
        microphoneEnabled = defaults.bool(forKey: Keys.microphone)
        microphonePreference = MicrophonePreference(rawValue: defaults.string(forKey: Keys.micPreference) ?? "") ?? .automatic
        simulationModeEnabled = defaults.bool(forKey: Keys.simulation)
        simulationScenario = SimulationScenario(rawValue: defaults.string(forKey: Keys.scenario) ?? "") ?? .approachingTraffic
        useRadarSimulator = defaults.bool(forKey: Keys.radarSim)
        riderDisplayName = defaults.string(forKey: Keys.riderName) ?? "Rider"
        if let stored = defaults.string(forKey: Keys.riderID).flatMap(UUID.init(uuidString:)) {
            riderID = stored
        } else {
            riderID = UUID()
            defaults.set(riderID.uuidString, forKey: Keys.riderID)
        }
    }

    var detectorChoice: DetectorChoice {
        guard simulationModeEnabled else { return .experimentalAcoustic }
        return useRadarSimulator ? .radarSimulator : .simulation(simulationScenario)
    }

    private enum Keys {
        static let onboarding = "onboarding.completed.v1"
        static let spoken = "alerts.spoken"
        static let spokenHealth = "alerts.spokenHealth"
        static let spokenGroup = "alerts.spokenGroup"
        static let speakerFallback = "alerts.speakerFallback"
        static let duck = "alerts.duckOthers"
        static let units = "units"
        static let consent = "samples.consent"
        static let microphone = "mic.enabled"
        static let micPreference = "mic.preference"
        static let simulation = "dev.simulation"
        static let scenario = "dev.scenario"
        static let radarSim = "dev.radarSimulator"
        static let riderName = "rider.name"
        static let riderID = "rider.id"
    }
}
