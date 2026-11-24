import Foundation

/// Every sentence the app can speak, in one place, so wording can be reviewed and tested.
///
/// Wording rules: no claims of safety, clearance, direction, distance or speed. Simulated
/// output always starts with "Simulation."
enum AlertPhrase: Equatable, Sendable {
    enum RideStartMode: Equatable, Sendable {
        case monitoring
        case simulation
        case detectionUnavailable
    }

    case detection(DetectionKind, simulated: Bool)
    case rideStarted(RideStartMode)
    case rideEnded
    case monitoringStopped(reason: String)
    case monitoringResumed
    case headphonesDisconnected
    case groupReport(senderName: String, kind: GroupReportKind)
    case testPrompt

    var text: String {
        switch self {
        case .detection(let kind, let simulated):
            let body = switch kind {
            case .possibleVehicleSound: "Possible vehicle sound."
            case .simulatedRadarTarget: "Radar target reported."
            }
            return simulated ? "Simulation. \(body)" : body
        case .rideStarted(.monitoring):
            return "Ride started. Experimental monitoring on."
        case .rideStarted(.simulation):
            return "Ride started. Simulation mode. Alerts are not real."
        case .rideStarted(.detectionUnavailable):
            return "Ride started. Vehicle detection is not available."
        case .rideEnded:
            return "Ride ended."
        case .monitoringStopped(let reason):
            return reason.isEmpty ? "Monitoring stopped." : "Monitoring stopped. \(reason)."
        case .monitoringResumed:
            return "Monitoring resumed."
        case .headphonesDisconnected:
            return "Headphones disconnected."
        case .groupReport(let senderName, let kind):
            return "\(senderName) \(kind.spokenPredicate)."
        case .testPrompt:
            return "RideAware test prompt."
        }
    }

    /// Fragments that must never appear in app-authored speech.
    static let prohibitedFragments = [
        "all clear", "clear", "safe", "car behind", "behind you", "meters", "metres",
        "feet away", "no traffic", "no vehicles", "nothing detected",
    ]
}
