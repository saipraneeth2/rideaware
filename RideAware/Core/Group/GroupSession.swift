import Foundation
import Observation

/// In-memory registry of groups reachable without a network. Milestone 3 replaces this with a
/// backend; the `GroupSession` API stays the same.
@MainActor
final class LocalGroupRegistry {
    private var groupsByCode: [String: RideGroup] = [:]

    func register(_ group: RideGroup) {
        groupsByCode[group.invite.value] = group
    }

    func lookup(code: String) -> RideGroup? {
        groupsByCode[code]
    }
}

/// Current private ride group: create/join/leave, presence and rider reports.
@MainActor
@Observable
final class GroupSession {
    private(set) var group: RideGroup?
    private(set) var feed: [GroupReport] = []
    private(set) var presence: [RiderPresence] = []
    let transportStatus: GroupTransportStatus = .localOnly
    var localRider: RiderIdentity

    /// Called for reports from other riders, after attribution. Used for speech.
    @ObservationIgnored var onRemoteReport: (@MainActor (GroupReport) -> Void)?
    /// Called after the rider leaves, so dependent features (location sharing) stop at once.
    @ObservationIgnored var onLeave: (@MainActor () -> Void)?
    @ObservationIgnored var onJoin: (@MainActor () -> Void)?

    @ObservationIgnored private let registry: LocalGroupRegistry
    @ObservationIgnored private let now: () -> Date
    private let feedLimit = 50

    init(localRider: RiderIdentity, registry: LocalGroupRegistry = LocalGroupRegistry(), now: @escaping () -> Date = Date.init) {
        self.localRider = localRider
        self.registry = registry
        self.now = now
    }

    var isInGroup: Bool { group != nil }

    @discardableResult
    func createGroup(name: String) throws -> RideGroup {
        guard group == nil else { throw GroupJoinError.alreadyInGroup }
        let date = now()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newGroup = RideGroup(
            id: UUID(),
            name: trimmed.isEmpty ? "Group ride" : trimmed,
            invite: InviteCode.generate(now: date),
            createdAt: date
        )
        registry.register(newGroup)
        enter(newGroup, at: date)
        return newGroup
    }

    @discardableResult
    func join(code input: String) throws -> RideGroup {
        guard group == nil else { throw GroupJoinError.alreadyInGroup }
        guard let code = InviteCode.normalize(input) else { throw GroupJoinError.malformedCode }
        guard let found = registry.lookup(code: code) else { throw GroupJoinError.notFound }
        let date = now()
        guard !found.invite.isExpired(at: date) else { throw GroupJoinError.expired }
        enter(found, at: date)
        return found
    }

    func leave() {
        guard group != nil else { return }
        group = nil
        feed.removeAll()
        presence.removeAll()
        onLeave?()
    }

    /// Sends a report from the local rider. Local reports are shown as "You" and not spoken.
    func send(_ kind: GroupReportKind) {
        guard let group else { return }
        let date = now()
        append(GroupReport(id: UUID(), groupID: group.id, kind: kind, sender: localRider, sentAt: date, receivedAt: date))
    }

    /// Entry point for reports arriving from a transport (or the simulator).
    func receive(kind: GroupReportKind, from sender: RiderIdentity, sentAt: Date, id: UUID = UUID()) {
        guard let group else { return }
        guard sender.id != localRider.id else { return } // Echo of our own report.
        guard !feed.contains(where: { $0.id == id }) else { return } // Duplicate delivery.
        let report = GroupReport(id: id, groupID: group.id, kind: kind, sender: sender, sentAt: sentAt, receivedAt: now())
        markSeen(sender, at: report.receivedAt)
        append(report)
        onRemoteReport?(report)
    }

    // MARK: Simulation (explicitly labelled)

    @discardableResult
    func addSimulatedRider() -> RiderIdentity? {
        guard group != nil else { return nil }
        let number = presence.filter { $0.rider.isSimulated }.count + 1
        let rider = RiderIdentity(id: UUID(), displayName: "Sim Rider \(number)", isSimulated: true)
        markSeen(rider, at: now())
        return rider
    }

    func sendSimulatedReport(_ kind: GroupReportKind) {
        let rider = presence.first(where: { $0.rider.isSimulated })?.rider ?? addSimulatedRider()
        guard let rider else { return }
        receive(kind: kind, from: rider, sentAt: now())
    }

    // MARK: Private

    private func enter(_ group: RideGroup, at date: Date) {
        self.group = group
        feed.removeAll()
        presence = [RiderPresence(rider: localRider, lastSeenAt: date, state: .connected)]
        onJoin?()
    }

    private func append(_ report: GroupReport) {
        feed.insert(report, at: 0)
        if feed.count > feedLimit { feed.removeLast(feed.count - feedLimit) }
    }

    private func markSeen(_ rider: RiderIdentity, at date: Date) {
        if let index = presence.firstIndex(where: { $0.rider.id == rider.id }) {
            presence[index].lastSeenAt = date
            presence[index].state = .connected
        } else {
            presence.append(RiderPresence(rider: rider, lastSeenAt: date, state: .connected))
        }
    }
}
