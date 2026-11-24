import Foundation

/// Timing rules for spoken detection alerts.
struct AlertPolicy: Sendable, Equatable {
    /// Events observed longer ago than this are rejected as stale.
    var maxEventAge: TimeInterval = 2.0
    /// Events time-stamped further than this in the future are rejected (clock or pipeline fault).
    var maxFutureSkew: TimeInterval = 0.5
    /// Events with the same de-duplication key within this window are one observation.
    /// The window slides: a continuous sound reported every 0.5 s stays one alert.
    var dedupWindow: TimeInterval = 4.0
    /// Minimum time between spoken alerts of the same kind.
    var cooldown: TimeInterval = 10.0
}

enum AlertDecision: Equatable, Sendable {
    case announce
    case duplicate
    case coolingDown(remaining: TimeInterval)
    case stale(age: TimeInterval)
    case futureTimestamp(skew: TimeInterval)

    var isRejection: Bool {
        switch self {
        case .stale, .futureTimestamp: true
        default: false
        }
    }

    var label: String {
        switch self {
        case .announce: "Announced"
        case .duplicate: "Suppressed: duplicate"
        case .coolingDown(let remaining): "Suppressed: cooldown (\(Int(remaining.rounded(.up))) s left)"
        case .stale(let age): String(format: "Rejected: stale (%.1f s old)", age)
        case .futureTimestamp(let skew): String(format: "Rejected: timestamp %.1f s in future", skew)
        }
    }
}

/// Applies `AlertPolicy` to a stream of detection events. Value type, deterministic, no I/O.
struct AlertGate: Sendable {
    let policy: AlertPolicy
    private var lastSeenByKey: [String: Date] = [:]
    private var lastAnnouncedByKind: [DetectionKind: Date] = [:]

    init(policy: AlertPolicy = AlertPolicy()) {
        self.policy = policy
    }

    mutating func evaluate(_ event: DetectionEvent, now: Date) -> AlertDecision {
        let age = event.age(at: now)
        if age < -policy.maxFutureSkew {
            return .futureTimestamp(skew: -age)
        }
        if age > policy.maxEventAge {
            // Stale events do not update de-duplication or cooldown state.
            return .stale(age: age)
        }

        let key = event.dedupKey
        if let lastSeen = lastSeenByKey[key],
           abs(event.sourceTimestamp.timeIntervalSince(lastSeen)) < policy.dedupWindow {
            lastSeenByKey[key] = max(lastSeen, event.sourceTimestamp)
            return .duplicate
        }
        lastSeenByKey[key] = event.sourceTimestamp

        if let lastAnnounced = lastAnnouncedByKind[event.kind] {
            let elapsed = now.timeIntervalSince(lastAnnounced)
            if elapsed < policy.cooldown {
                return .coolingDown(remaining: policy.cooldown - elapsed)
            }
        }
        lastAnnouncedByKind[event.kind] = now
        prune(now: now)
        return .announce
    }

    private mutating func prune(now: Date) {
        let horizon = max(policy.dedupWindow, policy.maxEventAge) * 4
        lastSeenByKey = lastSeenByKey.filter { now.timeIntervalSince($0.value) < horizon }
    }
}
