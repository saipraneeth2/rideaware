import Foundation

struct RiderIdentity: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    var displayName: String
    /// Simulated riders exist only for testing the UI and attribution.
    var isSimulated: Bool = false
}

/// Explicit, rider-generated group messages. These are reports from people, not sensor output.
enum GroupReportKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case slowing
    case stopping
    case hazard
    case needHelp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slowing: "Slowing"
        case .stopping: "Stopping"
        case .hazard: "Hazard reported"
        case .needHelp: "Need help"
        }
    }

    var systemImage: String {
        switch self {
        case .slowing: "tortoise.fill"
        case .stopping: "hand.raised.fill"
        case .hazard: "exclamationmark.triangle.fill"
        case .needHelp: "sos"
        }
    }

    /// Completes "<name> …" for speech.
    var spokenPredicate: String {
        switch self {
        case .slowing: "is slowing"
        case .stopping: "is stopping"
        case .hazard: "reports a hazard"
        case .needHelp: "needs help"
        }
    }
}

enum ReportOrigin: Equatable, Sendable {
    case you
    case otherRider(name: String, simulated: Bool)

    var label: String {
        switch self {
        case .you: "You"
        case .otherRider(let name, let simulated): simulated ? "\(name) (simulated rider)" : name
        }
    }
}

/// A message from a rider. Always shown with its sender and age, and never presented as a
/// detection made by this phone.
struct GroupReport: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let groupID: UUID
    let kind: GroupReportKind
    let sender: RiderIdentity
    /// Sender's clock. Shown for diagnostics only because device clocks can differ.
    let sentAt: Date
    /// This device's clock. Age is computed from this.
    let receivedAt: Date

    func origin(localRiderID: UUID) -> ReportOrigin {
        sender.id == localRiderID ? .you : .otherRider(name: sender.displayName, simulated: sender.isSimulated)
    }

    func age(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(receivedAt))
    }
}

enum PresenceState: String, Sendable {
    case connected
    case stale
    case left
}

struct RiderPresence: Identifiable, Sendable, Equatable {
    var rider: RiderIdentity
    var lastSeenAt: Date
    var state: PresenceState
    var id: UUID { rider.id }
}

struct RideGroup: Identifiable, Sendable, Equatable {
    let id: UUID
    let name: String
    let invite: InviteCode
    let createdAt: Date
}

enum GroupJoinError: LocalizedError, Equatable {
    case malformedCode
    case expired
    case notFound
    case alreadyInGroup

    var errorDescription: String? {
        switch self {
        case .malformedCode: "That is not a valid code. Codes are 6 letters or digits, like ABC-234."
        case .expired: "This invitation has expired. Ask for a new code."
        case .notFound: "No group with that code is reachable. Without a network transport, only groups created on this iPhone can be joined."
        case .alreadyInGroup: "Leave the current group first."
        }
    }
}

/// Transport availability, shown in the UI so riders know what group features really do.
enum GroupTransportStatus: Equatable, Sendable {
    /// No network backend configured: groups, presence and reports stay on this device.
    case localOnly

    var label: String {
        switch self {
        case .localOnly: "Local only. No network transport is configured, so nothing leaves this iPhone."
        }
    }
}
