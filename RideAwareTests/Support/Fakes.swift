import Foundation
@testable import RideAware

/// Manually advanced clock.
final class TestClock: @unchecked Sendable {
    var now: Date
    init(_ start: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)) { now = start }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    var closure: () -> Date { { [unowned self] in self.now } }
}

@MainActor
final class FakeSpeaker: AlertSpeaking {
    private(set) var spoken: [AlertPhrase] = []
    func speak(_ phrase: AlertPhrase, priority: SpeechPriority) { spoken.append(phrase) }
}

@MainActor
final class FakeMicrophone: MicrophoneMonitoring {
    var health: StreamHealth = .off
    var isRunning = false
    var healthWhenStarted: StreamHealth = .live(lastInputAge: 0)
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() async {
        startCount += 1
        isRunning = healthWhenStarted.isLive
        health = healthWhenStarted
    }

    func stop() {
        stopCount += 1
        isRunning = false
        health = .off
    }

    func evaluateHealth(now: Date) {}
}

@MainActor
final class FakeDetector: DetectionProvider {
    var descriptor = DetectorDescriptor(kind: .simulated, name: "Fake detector", isSimulated: true, summary: "")
    var availability: DetectorAvailability = .ready
    var isRunning = false
    var lastInputAt: Date?
    var failureReason: String?
    var onEvent: (@MainActor (DetectionEvent) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() { startCount += 1; isRunning = true }
    func stop() { stopCount += 1; isRunning = false }
    func emit(_ event: DetectionEvent) { onEvent?(event) }
}

@MainActor
final class FakeLocationProvider: LocationProviding {
    private(set) var isUpdating = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    func startUpdates() { startCount += 1; isUpdating = true }
    func stopUpdates() { stopCount += 1; isUpdating = false }
}

@MainActor
final class FakePermission: MicrophonePermissionProviding {
    var state: MicrophonePermissionState
    var grantOnRequest: Bool
    private(set) var requestCount = 0

    init(state: MicrophonePermissionState, grantOnRequest: Bool = false) {
        self.state = state
        self.grantOnRequest = grantOnRequest
    }

    func request() async -> Bool {
        requestCount += 1
        state = grantOnRequest ? .granted : .denied
        return grantOnRequest
    }
}

final class InMemoryRideStore: RideStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [RideSession] = []
    private(set) var saveCount = 0

    func load() throws -> [RideSession] { lock.withLock { stored } }
    func save(_ rides: [RideSession]) throws {
        lock.withLock {
            stored = rides
            saveCount += 1
        }
    }
}

/// Deterministic RNG for reproducible invite codes.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func makeEvent(
    kind: DetectionKind = .possibleVehicleSound,
    source: DetectionSource = .experimentalAcoustic(modelName: "test"),
    observedAt: Date,
    receivedAt: Date? = nil,
    correlationID: String? = nil
) -> DetectionEvent {
    DetectionEvent(kind: kind, source: source, sourceTimestamp: observedAt,
                   receivedAt: receivedAt ?? observedAt, correlationID: correlationID)
}
