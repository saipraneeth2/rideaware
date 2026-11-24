import Foundation

/// Explicitly labelled simulation scenarios. Every event they produce is marked as simulated
/// in the UI, in spoken alerts ("Simulation. …") and in stored ride sessions.
enum SimulationScenario: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case approachingTraffic
    case repeatedDetections
    case silence
    case sensorFailure
    case staleInput

    var id: String { rawValue }

    var title: String {
        switch self {
        case .approachingTraffic: "Approaching traffic"
        case .repeatedDetections: "Repeated detections"
        case .silence: "Silence"
        case .sensorFailure: "Sensor failure"
        case .staleInput: "Stale input"
        }
    }

    var detail: String {
        switch self {
        case .approachingTraffic:
            "Two simulated approaches per 45 s cycle. Each approach emits several frames that should be de-duplicated into one alert."
        case .repeatedDetections:
            "A burst of duplicate frames, a second sound inside the cooldown, then a third after it. Exercises de-duplication and cooldown."
        case .silence:
            "The simulated sensor stays healthy and reports nothing. The app must not present this as a clear road."
        case .sensorFailure:
            "Input stops after 8 s (becomes stale), then the sensor reports a failure at 14 s."
        case .staleInput:
            "Events arrive 6 s after they were observed and must be rejected; one fresh event at 25 s is accepted."
        }
    }

    var script: SimulationScript {
        switch self {
        case .approachingTraffic:
            SimulationScript(
                steps: Self.burst(id: "approach-a", from: 6, through: 8, every: 0.5)
                    + Self.burst(id: "approach-b", from: 26, through: 28, every: 0.5),
                loopAfter: 45
            )
        case .repeatedDetections:
            SimulationScript(
                steps: Self.burst(id: "burst-1", from: 4, through: 7.5, every: 0.5)
                    + [SimulationStep(at: 9, action: .event(correlationID: "second-sound", sourceDelay: 0))]
                    + [SimulationStep(at: 16, action: .event(correlationID: "third-sound", sourceDelay: 0))],
                loopAfter: 40
            )
        case .silence:
            SimulationScript(steps: [], loopAfter: nil)
        case .sensorFailure:
            SimulationScript(
                steps: [
                    SimulationStep(at: 4, action: .event(correlationID: "before-failure", sourceDelay: 0)),
                    SimulationStep(at: 8, action: .stopHeartbeat),
                    SimulationStep(at: 14, action: .fail(reason: "Simulated sensor failure")),
                ],
                loopAfter: nil
            )
        case .staleInput:
            SimulationScript(
                steps: [
                    SimulationStep(at: 5, action: .event(correlationID: "late-1", sourceDelay: 6)),
                    SimulationStep(at: 15, action: .event(correlationID: "late-2", sourceDelay: 6)),
                    SimulationStep(at: 25, action: .event(correlationID: "fresh", sourceDelay: 0)),
                ],
                loopAfter: 35
            )
        }
    }

    private static func burst(id: String, from start: TimeInterval, through end: TimeInterval, every interval: TimeInterval) -> [SimulationStep] {
        stride(from: start, through: end, by: interval).map {
            SimulationStep(at: $0, action: .event(correlationID: id, sourceDelay: 0))
        }
    }
}

struct SimulationStep: Sendable, Equatable {
    enum Action: Sendable, Equatable {
        /// Emit a `possibleVehicleSound` event observed `sourceDelay` seconds before delivery.
        case event(correlationID: String, sourceDelay: TimeInterval)
        /// Stop reporting input, so health becomes stale.
        case stopHeartbeat
        /// Report a provider fault.
        case fail(reason: String)
    }

    /// Seconds from the start of the cycle.
    let at: TimeInterval
    let action: Action
}

struct SimulationScript: Sendable, Equatable {
    var steps: [SimulationStep]
    /// Restart the script after this many seconds; `nil` runs it once.
    var loopAfter: TimeInterval?
}

/// Plays a `SimulationScript` in real time. `advance(to:)` is deterministic so tests can drive
/// the provider with synthetic clocks.
@MainActor
final class SimulatedDetectionProvider: DetectionProvider {
    let scenario: SimulationScenario
    let descriptor: DetectorDescriptor
    let availability: DetectorAvailability = .ready
    private(set) var isRunning = false
    private(set) var lastInputAt: Date?
    private(set) var failureReason: String?
    var onEvent: (@MainActor (DetectionEvent) -> Void)?

    private let script: SimulationScript
    private let now: () -> Date
    private var startedAt: Date?
    private var cycleStart: Date?
    private var cycle = 0
    private var nextStepIndex = 0
    private var heartbeatActive = true
    private var ticker: Task<Void, Never>?

    init(scenario: SimulationScenario, now: @escaping () -> Date = Date.init) {
        self.scenario = scenario
        self.script = scenario.script
        self.now = now
        self.descriptor = DetectorDescriptor(
            kind: .simulated,
            name: "Simulation: \(scenario.title)",
            isSimulated: true,
            summary: "Scripted events for testing. Nothing here comes from a real sensor."
        )
    }

    func start() {
        start(at: now(), runClock: true)
    }

    /// Starts without a real-time clock. Tests call `advance(to:)` directly.
    func start(at date: Date, runClock: Bool) {
        stop()
        isRunning = true
        failureReason = nil
        heartbeatActive = true
        startedAt = date
        cycleStart = date
        cycle = 0
        nextStepIndex = 0
        lastInputAt = date
        if runClock {
            ticker = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard let self else { return }
                    self.advance(to: self.now())
                }
            }
        }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        isRunning = false
    }

    func advance(to date: Date) {
        guard isRunning, var cycleStart else { return }

        while true {
            let elapsed = date.timeIntervalSince(cycleStart)
            while nextStepIndex < script.steps.count, script.steps[nextStepIndex].at <= elapsed {
                let step = script.steps[nextStepIndex]
                nextStepIndex += 1
                perform(step, scheduledAt: cycleStart.addingTimeInterval(step.at), deliveredAt: date)
                if !isRunning { return }
            }
            guard let loop = script.loopAfter, elapsed >= loop else { break }
            cycleStart = cycleStart.addingTimeInterval(loop)
            self.cycleStart = cycleStart
            cycle += 1
            nextStepIndex = 0
        }

        if heartbeatActive {
            lastInputAt = date
        }
    }

    private func perform(_ step: SimulationStep, scheduledAt: Date, deliveredAt: Date) {
        switch step.action {
        case .event(let correlationID, let sourceDelay):
            let event = DetectionEvent(
                kind: .possibleVehicleSound,
                source: .simulation(scenario: scenario),
                sourceTimestamp: scheduledAt.addingTimeInterval(-sourceDelay),
                receivedAt: deliveredAt,
                correlationID: "\(correlationID)#\(cycle)"
            )
            onEvent?(event)
        case .stopHeartbeat:
            heartbeatActive = false
        case .fail(let reason):
            failureReason = reason
            heartbeatActive = false
            ticker?.cancel()
            ticker = nil
            isRunning = false
        }
    }
}
