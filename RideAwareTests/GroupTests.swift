import Foundation
import Testing
@testable import RideAware

@Suite("Invitation codes")
struct InviteCodeTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func generatedCodesUseUnambiguousAlphabet() {
        var rng = SplitMix64(state: 42)
        for _ in 0..<200 {
            let code = InviteCode.generate(now: t0, using: &rng)
            #expect(code.value.count == InviteCode.length)
            #expect(code.value.allSatisfy(InviteCode.alphabet.contains))
            #expect(!code.value.contains { "01OIL".contains($0) })
        }
    }

    @Test func normalizationAcceptsCommonTypingVariations() {
        #expect(InviteCode.normalize("abc-234") == "ABC234")
        #expect(InviteCode.normalize(" ABC 234 ") == "ABC234")
        #expect(InviteCode.normalize("ABC23") == nil)
        #expect(InviteCode.normalize("ABC23O") == nil) // letter O is excluded
        #expect(InviteCode.normalize("ABC2345") == nil)
    }

    @Test func expiryIsInclusiveOfDeadline() {
        let code = InviteCode(value: "ABC234", expiresAt: t0)
        #expect(!code.isExpired(at: t0.addingTimeInterval(-1)))
        #expect(code.isExpired(at: t0))
        #expect(code.formatted == "ABC-234")
    }
}

@MainActor
@Suite("Group create, join and leave")
struct GroupFlowTests {
    let me = RiderIdentity(id: UUID(), displayName: "Me")

    @Test func joinWithCodeFromRegistry() throws {
        let clock = TestClock()
        let registry = LocalGroupRegistry()
        let host = GroupSession(localRider: RiderIdentity(id: UUID(), displayName: "Host"), registry: registry, now: clock.closure)
        let created = try host.createGroup(name: "Sunday loop")
        let guest = GroupSession(localRider: me, registry: registry, now: clock.closure)
        let joined = try guest.join(code: created.invite.formatted.lowercased())
        #expect(joined.id == created.id)
        #expect(guest.presence.map(\.rider.id) == [me.id])
    }

    @Test func expiredCodeIsRejected() throws {
        let clock = TestClock()
        let registry = LocalGroupRegistry()
        let host = GroupSession(localRider: RiderIdentity(id: UUID(), displayName: "Host"), registry: registry, now: clock.closure)
        let created = try host.createGroup(name: "Loop")
        clock.advance(InviteCode.defaultLifetime + 1)
        let guest = GroupSession(localRider: me, registry: registry, now: clock.closure)
        #expect(throws: GroupJoinError.expired) { try guest.join(code: created.invite.value) }
        #expect(!guest.isInGroup)
    }

    @Test func malformedAndUnknownCodesAreRejected() {
        let guest = GroupSession(localRider: me)
        #expect(throws: GroupJoinError.malformedCode) { try guest.join(code: "nope") }
        #expect(throws: GroupJoinError.notFound) { try guest.join(code: "ABC-234") }
    }

    @Test func cannotJoinWhileInAGroup() throws {
        let session = GroupSession(localRider: me)
        try session.createGroup(name: "A")
        #expect(throws: GroupJoinError.alreadyInGroup) { try session.createGroup(name: "B") }
    }
}

@MainActor
@Suite("Group report attribution")
struct GroupAttributionTests {
    let me = RiderIdentity(id: UUID(), displayName: "Me")
    let alex = RiderIdentity(id: UUID(), displayName: "Alex")

    func makeWired(clock: TestClock) throws -> (GroupSession, AlertCoordinator, FakeSpeaker) {
        let speaker = FakeSpeaker()
        let alerts = AlertCoordinator(speaker: speaker, now: clock.closure)
        let group = GroupSession(localRider: me, now: clock.closure)
        group.onRemoteReport = { report in
            alerts.notify(.groupReport(senderName: report.sender.displayName, kind: report.kind), category: .group)
        }
        try group.createGroup(name: "Ride")
        return (group, alerts, speaker)
    }

    @Test func remoteReportKeepsSenderAndIsNeverALocalDetection() throws {
        let clock = TestClock()
        let (group, alerts, speaker) = try makeWired(clock: clock)
        group.receive(kind: .hazard, from: alex, sentAt: clock.now)

        #expect(group.feed.count == 1)
        #expect(group.feed[0].origin(localRiderID: me.id) == .otherRider(name: "Alex", simulated: false))
        #expect(speaker.spoken == [.groupReport(senderName: "Alex", kind: .hazard)])
        #expect(speaker.spoken[0].text == "Alex reports a hazard.")
        // Not routed through detection: no detection log, nothing announced as a vehicle.
        #expect(alerts.log.isEmpty)
        #expect(alerts.lastAnnounced == nil)
        #expect(alerts.counts == AlertCounts())
    }

    @Test func ageUsesLocalReceiveTimeNotSenderClock() throws {
        let clock = TestClock()
        let (group, _, _) = try makeWired(clock: clock)
        // Sender's clock is 5 minutes behind.
        group.receive(kind: .slowing, from: alex, sentAt: clock.now.addingTimeInterval(-300))
        clock.advance(12)
        #expect(group.feed[0].age(at: clock.now) == 12)
    }

    @Test func localReportIsAttributedToYouAndNotSpoken() throws {
        let clock = TestClock()
        let (group, _, speaker) = try makeWired(clock: clock)
        group.send(.stopping)
        #expect(group.feed[0].origin(localRiderID: me.id) == .you)
        #expect(speaker.spoken.isEmpty)
    }

    @Test func echoOfOwnReportAndDuplicateDeliveryAreIgnored() throws {
        let clock = TestClock()
        let (group, _, speaker) = try makeWired(clock: clock)
        group.receive(kind: .hazard, from: me, sentAt: clock.now)
        let id = UUID()
        group.receive(kind: .needHelp, from: alex, sentAt: clock.now, id: id)
        group.receive(kind: .needHelp, from: alex, sentAt: clock.now, id: id)
        #expect(group.feed.count == 1)
        #expect(speaker.spoken.count == 1)
    }

    @Test func simulatedRiderIsLabelledAsSimulated() throws {
        let clock = TestClock()
        let (group, _, _) = try makeWired(clock: clock)
        group.sendSimulatedReport(.hazard)
        let origin = group.feed[0].origin(localRiderID: me.id)
        #expect(origin.label.contains("simulated"))
    }

    @Test func reportsAreIgnoredOutsideAGroup() {
        let group = GroupSession(localRider: me)
        group.receive(kind: .hazard, from: alex, sentAt: Date())
        #expect(group.feed.isEmpty)
    }
}
