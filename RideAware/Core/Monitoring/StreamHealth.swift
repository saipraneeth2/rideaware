import Foundation

/// Health of one input stream (microphone or detector), kept separate from the events it carries.
enum StreamHealth: Equatable, Sendable {
    case off
    /// Running, waiting for the first input within the start-up grace period.
    case starting
    case live(lastInputAge: TimeInterval)
    /// Running but no input recently. `nil` age means no input since start.
    case stale(lastInputAge: TimeInterval?)
    case interrupted(reason: String)
    case unavailable(reason: String)
    case failed(reason: String)

    enum Severity: Sendable, Comparable {
        case ok, info, warning, critical
    }

    var isLive: Bool {
        if case .live = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .off: "Off"
        case .starting: "Starting"
        case .live: "Live"
        case .stale: "Stale"
        case .interrupted: "Interrupted"
        case .unavailable: "Unavailable"
        case .failed: "Failed"
        }
    }

    var detail: String {
        switch self {
        case .off: "Not running"
        case .starting: "Waiting for first input"
        case .live: "Receiving input"
        case .stale(let age?): "No input for \(Int(age.rounded())) s"
        case .stale(nil): "No input received"
        case .interrupted(let reason), .unavailable(let reason), .failed(let reason): reason
        }
    }

    var severity: Severity {
        switch self {
        case .live: .ok
        case .off, .starting: .info
        case .stale, .interrupted: .warning
        case .unavailable, .failed: .critical
        }
    }

    var systemImage: String {
        switch self {
        case .live: "checkmark.circle.fill"
        case .off: "pause.circle"
        case .starting: "hourglass"
        case .stale: "clock.badge.exclamationmark"
        case .interrupted: "phone.arrow.down.left"
        case .unavailable: "nosign"
        case .failed: "xmark.octagon.fill"
        }
    }
}

/// Turns raw stream facts into a `StreamHealth`. Pure and deterministic for testing.
struct StreamHealthEvaluator: Sendable, Equatable {
    /// Input older than this is stale.
    var staleAfter: TimeInterval
    /// Time allowed after start before missing input counts as stale.
    var startupGrace: TimeInterval

    func evaluate(
        isRunning: Bool,
        startedAt: Date?,
        lastInputAt: Date?,
        now: Date,
        interruptedReason: String? = nil,
        unavailableReason: String? = nil,
        failureReason: String? = nil
    ) -> StreamHealth {
        if let unavailableReason { return .unavailable(reason: unavailableReason) }
        if let failureReason { return .failed(reason: failureReason) }
        if let interruptedReason { return .interrupted(reason: interruptedReason) }
        guard isRunning else { return .off }

        // Ignore input that predates the current start (e.g. from before a restart).
        var effectiveLastInput = lastInputAt
        if let startedAt, let last = lastInputAt, last < startedAt {
            effectiveLastInput = nil
        }

        if let last = effectiveLastInput {
            let age = max(0, now.timeIntervalSince(last))
            return age <= staleAfter ? .live(lastInputAge: age) : .stale(lastInputAge: age)
        }
        if let startedAt, now.timeIntervalSince(startedAt) <= startupGrace {
            return .starting
        }
        return .stale(lastInputAge: nil)
    }
}
