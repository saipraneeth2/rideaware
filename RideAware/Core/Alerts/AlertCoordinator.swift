import Foundation
import Observation

enum SpeechPriority: Sendable {
    /// Detection alerts: may cut off a lower-priority sentence.
    case high
    case normal
}

/// Speaks alert phrases. Implemented by `SpeechAlertSpeaker`; faked in tests.
@MainActor
protocol AlertSpeaking: AnyObject {
    func speak(_ phrase: AlertPhrase, priority: SpeechPriority)
}

/// Category used to apply the rider's spoken-alert settings.
enum AnnouncementCategory: Sendable {
    case detection
    case health
    case ride
    case group
    case test
}

struct AlertLogEntry: Identifiable, Sendable, Equatable {
    let id = UUID()
    let event: DetectionEvent
    let decision: AlertDecision
    let decidedAt: Date
    let spoken: Bool
}

struct NoticeLogEntry: Identifiable, Sendable, Equatable {
    let id = UUID()
    let phrase: AlertPhrase
    let at: Date
    let spoken: Bool
}

struct AlertCounts: Sendable, Equatable, Codable {
    var announced = 0
    var duplicates = 0
    var cooldownSuppressed = 0
    var rejectedStale = 0
    var rejectedOther = 0

    var suppressed: Int { duplicates + cooldownSuppressed }
}

/// Routes local detection events through `AlertGate` and speaks the result.
///
/// Group reports never pass through here as detections; they are spoken with
/// `notify(_:category:)` using `.groupReport`, which names the sending rider.
@MainActor
@Observable
final class AlertCoordinator {
    private(set) var log: [AlertLogEntry] = []
    private(set) var notices: [NoticeLogEntry] = []
    private(set) var lastAnnounced: AlertLogEntry?
    private(set) var counts = AlertCounts()

    /// Decides whether a category may be spoken right now (settings, output route).
    @ObservationIgnored var isSpeechAllowed: @MainActor (AnnouncementCategory) -> Bool = { _ in true }

    @ObservationIgnored private var gate: AlertGate
    @ObservationIgnored private let speaker: any AlertSpeaking
    @ObservationIgnored private let now: () -> Date
    private let logLimit = 100

    init(speaker: any AlertSpeaking, policy: AlertPolicy = AlertPolicy(), now: @escaping () -> Date = Date.init) {
        self.speaker = speaker
        self.gate = AlertGate(policy: policy)
        self.now = now
    }

    var policy: AlertPolicy { gate.policy }

    @discardableResult
    func handle(_ event: DetectionEvent) -> AlertDecision {
        let decidedAt = now()
        let decision = gate.evaluate(event, now: decidedAt)
        var spoken = false
        switch decision {
        case .announce:
            counts.announced += 1
            if isSpeechAllowed(.detection) {
                speaker.speak(.detection(event.kind, simulated: event.source.isSimulated), priority: .high)
                spoken = true
            }
        case .duplicate:
            counts.duplicates += 1
        case .coolingDown:
            counts.cooldownSuppressed += 1
        case .stale:
            counts.rejectedStale += 1
        case .futureTimestamp:
            counts.rejectedOther += 1
        }
        let entry = AlertLogEntry(event: event, decision: decision, decidedAt: decidedAt, spoken: spoken)
        log.insert(entry, at: 0)
        if log.count > logLimit { log.removeLast(log.count - logLimit) }
        if decision == .announce { lastAnnounced = entry }
        return decision
    }

    /// Speaks a non-detection message (ride, health, group, test).
    func notify(_ phrase: AlertPhrase, category: AnnouncementCategory) {
        let spoken = isSpeechAllowed(category)
        if spoken {
            speaker.speak(phrase, priority: .normal)
        }
        notices.insert(NoticeLogEntry(phrase: phrase, at: now(), spoken: spoken), at: 0)
        if notices.count > logLimit { notices.removeLast(notices.count - logLimit) }
    }

    func resetForNewRide() {
        gate = AlertGate(policy: gate.policy)
        log.removeAll()
        lastAnnounced = nil
        counts = AlertCounts()
    }
}
