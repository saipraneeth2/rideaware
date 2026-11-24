import Foundation

/// What the rider is told about monitoring, separate from traffic events.
///
/// "Monitoring active" requires a *live detector*. A working microphone on its own is not
/// vehicle detection and is never presented as such.
struct MonitoringSnapshot: Equatable, Sendable {
    var isRiding: Bool
    var detector: StreamHealth
    var detectorName: String
    var detectorIsSimulated: Bool
    var microphone: StreamHealth

    static let idle = MonitoringSnapshot(
        isRiding: false,
        detector: .off,
        detectorName: "None",
        detectorIsSimulated: false,
        microphone: .off
    )

    var isMonitoringActive: Bool { isRiding && detector.isLive }

    var headline: String {
        guard isRiding else { return "Not riding" }
        if detector.isLive {
            return detectorIsSimulated ? "Simulated monitoring active" : "Experimental monitoring active"
        }
        if detector == .starting { return "Monitoring starting" }
        return "Not monitoring for vehicles"
    }

    /// Short reason suitable for speech when monitoring is not active.
    var inactiveReason: String {
        switch detector {
        case .unavailable(let reason), .failed(let reason), .interrupted(let reason): reason
        case .stale: "Detector input is stale"
        case .off: "Detector is off"
        case .starting: "Detector is starting"
        case .live: ""
        }
    }

    var severity: StreamHealth.Severity {
        guard isRiding else { return .info }
        return detector.isLive ? .ok : max(detector.severity, .warning)
    }
}

/// Decides when to tell the rider, by voice, that monitoring stopped or resumed.
///
/// It tracks the state last *announced*. A change is spoken once it is observed, unless another
/// health announcement was made within `minimumInterval`; then it is spoken on a later update if
/// the change persists. Brief flaps shorter than the interval are therefore not spoken twice.
/// It never announces anything that implies the road is clear.
struct HealthAnnouncer: Sendable {
    var minimumInterval: TimeInterval = 10
    private var announcedActive: Bool?
    private var lastAnnouncementAt: Date?

    init(minimumInterval: TimeInterval = 10) {
        self.minimumInterval = minimumInterval
    }

    mutating func update(_ snapshot: MonitoringSnapshot, now: Date) -> AlertPhrase? {
        guard snapshot.isRiding else {
            announcedActive = nil
            lastAnnouncementAt = nil
            return nil
        }
        let active = snapshot.isMonitoringActive
        // Starting is transient; wait for a definite state.
        if snapshot.detector == .starting { return nil }
        guard let announced = announcedActive else {
            // The ride-start announcement already described the initial state.
            announcedActive = active
            return nil
        }
        guard active != announced else { return nil }
        if let last = lastAnnouncementAt, now.timeIntervalSince(last) < minimumInterval {
            return nil
        }
        announcedActive = active
        lastAnnouncementAt = now
        return active ? .monitoringResumed : .monitoringStopped(reason: snapshot.inactiveReason)
    }
}
