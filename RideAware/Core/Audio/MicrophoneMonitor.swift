import Foundation
import Observation

/// What the ride needs from the microphone. Faked in tests.
@MainActor
protocol MicrophoneMonitoring: AnyObject {
    var health: StreamHealth { get }
    var isRunning: Bool { get }
    func start() async
    func stop()
    func evaluateHealth(now: Date)
}

/// Owns microphone permission, capture lifecycle and recovery from interruptions, route
/// changes and media-server resets. It requests the `.microphoneSensing` demand from the
/// coordinator and never touches `AVAudioSession` itself.
@MainActor
@Observable
final class MicrophoneMonitor: MicrophoneMonitoring {
    private(set) var permission: MicrophonePermissionState
    private(set) var isRunning = false
    private(set) var startedAt: Date?
    private(set) var lastBufferAt: Date?
    private(set) var level: InputLevel?
    private(set) var format: CaptureFormat?
    private(set) var buffersReceived = 0
    private(set) var restartCount = 0
    private(set) var interruptedReason: String?
    private(set) var failureReason: String?
    private(set) var unavailableReason: String?
    private(set) var health: StreamHealth = .off

    @ObservationIgnored private(set) var wantsRunning = false
    @ObservationIgnored private var lastStartAttemptAt: Date?
    @ObservationIgnored let capture: MicrophoneCapture
    @ObservationIgnored private let coordinator: AudioSessionCoordinator
    @ObservationIgnored private let permissions: any MicrophonePermissionProviding
    @ObservationIgnored let evaluator = StreamHealthEvaluator(staleAfter: 2.0, startupGrace: 3.0)
    @ObservationIgnored let retryInterval: TimeInterval = 5

    init(coordinator: AudioSessionCoordinator,
         permissions: any MicrophonePermissionProviding,
         capture: MicrophoneCapture = MicrophoneCapture()) {
        self.coordinator = coordinator
        self.permissions = permissions
        self.capture = capture
        self.permission = permissions.state

        capture.onFrames = { [weak self] info in
            Task { @MainActor [weak self] in self?.receive(info) }
        }
        capture.onConfigurationChange = { [weak self] in
            Task { @MainActor [weak self] in self?.handleEngineConfigurationChange() }
        }
        coordinator.addListener { [weak self] event in
            self?.handle(event)
        }
    }

    func refreshPermission() {
        permission = permissions.state
    }

    func start() async {
        wantsRunning = true
        failureReason = nil
        unavailableReason = nil
        interruptedReason = nil
        permission = permissions.state
        if permission == .undetermined {
            let granted = await permissions.request()
            permission = granted ? .granted : .denied
        }
        guard wantsRunning else { return }
        guard permission == .granted else {
            unavailableReason = "Microphone permission denied. Enable it in Settings › Privacy & Security › Microphone."
            evaluateHealth(now: Date())
            return
        }
        startCapture()
    }

    func stop() {
        wantsRunning = false
        capture.stop()
        coordinator.release(.microphoneSensing)
        isRunning = false
        startedAt = nil
        level = nil
        interruptedReason = nil
        failureReason = nil
        unavailableReason = nil
        health = .off
    }

    func evaluateHealth(now: Date) {
        if wantsRunning, !isRunning, interruptedReason == nil, unavailableReason == nil,
           let last = lastStartAttemptAt, now.timeIntervalSince(last) >= retryInterval {
            restartCount += 1
            startCapture()
        }
        health = evaluator.evaluate(
            isRunning: isRunning,
            startedAt: startedAt,
            lastInputAt: lastBufferAt,
            now: now,
            interruptedReason: interruptedReason,
            unavailableReason: unavailableReason,
            failureReason: failureReason
        )
    }

    private func startCapture() {
        lastStartAttemptAt = Date()
        do {
            try coordinator.acquire(.microphoneSensing)
        } catch {
            failureReason = "Audio session: \(error.localizedDescription)"
            isRunning = false
            evaluateHealth(now: Date())
            return
        }
        do {
            format = try capture.start()
            isRunning = true
            failureReason = nil
            startedAt = Date()
            coordinator.refreshRoute()
        } catch {
            failureReason = "Capture: \(error.localizedDescription)"
            isRunning = false
            coordinator.release(.microphoneSensing)
        }
        evaluateHealth(now: Date())
    }

    private func receive(_ info: CaptureFrameInfo) {
        guard isRunning else { return }
        lastBufferAt = info.receivedAt
        level = info.level
        buffersReceived += 1
    }

    private func handle(_ event: AudioSessionEvent) {
        guard wantsRunning else { return }
        switch event {
        case .interruptionBegan(let reason):
            capture.stop()
            isRunning = false
            interruptedReason = reason
        case .interruptionEnded:
            // Recording apps attempt to resume regardless of the playback-oriented hint.
            guard interruptedReason != nil else { return }
            interruptedReason = nil
            restartCount += 1
            startCapture()
        case .mediaServicesReset:
            capture.stop()
            isRunning = false
            restartCount += 1
            startCapture()
        case .routeChanged, .privateOutputLost:
            break // Engine configuration-change notifications drive capture restarts.
        }
        evaluateHealth(now: Date())
    }

    private func handleEngineConfigurationChange() {
        guard wantsRunning, interruptedReason == nil else { return }
        capture.stop()
        isRunning = false
        restartCount += 1
        startCapture()
    }

    // MARK: Samples

    func beginSampleRecording(to url: URL) throws {
        try capture.beginRecording(to: url)
    }

    func finishSampleRecording() -> (url: URL, duration: TimeInterval)? {
        capture.finishRecording()
    }

    var inputDescription: String {
        let route = coordinator.route.inputSummary
        if let format { return "\(route) · \(format.description)" }
        return route
    }
}
