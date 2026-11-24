import AVFAudio
import Foundation
import Observation

/// Events the coordinator forwards to features after normalising AVAudioSession notifications.
enum AudioSessionEvent: Sendable, Equatable {
    case interruptionBegan(reason: String)
    case interruptionEnded(shouldResume: Bool)
    case routeChanged(reason: String)
    /// Headphones (wired or Bluetooth) went away and audio now plays from a non-private output.
    case privateOutputLost(previousOutput: String)
    case mediaServicesReset
}

struct RouteChangeRecord: Sendable, Equatable {
    let reason: String
    let at: Date
}

struct SessionDetails: Sendable, Equatable {
    var category = ""
    var mode = ""
    var options = ""
    var sampleRate: Double = 0
    var ioBufferDuration: TimeInterval = 0
    var inputLatency: TimeInterval = 0
    var outputLatency: TimeInterval = 0
    var isOtherAudioPlaying = false
    var preferredInput: String?
}

/// The only object in the app that configures or activates `AVAudioSession`.
///
/// Capture, speech, sample playback and (future) voice chat each `acquire` a demand and
/// `release` it when done. The coordinator computes one plan for the combined demands with
/// `SessionPlanner` and applies it only when it changes, so features cannot overwrite each
/// other's settings.
@MainActor
@Observable
final class AudioSessionCoordinator {
    private(set) var route = AudioRouteSnapshot.empty
    private(set) var availableInputs: [AudioPortInfo] = []
    private(set) var activeDemands: Set<AudioDemand> = []
    private(set) var appliedPlan: SessionPlan?
    private(set) var isSessionActive = false
    private(set) var isInterrupted = false
    private(set) var lastInterruptionReason: String?
    private(set) var lastRouteChange: RouteChangeRecord?
    private(set) var lastError: String?
    private(set) var details = SessionDetails()
    private(set) var microphonePreference: MicrophonePreference
    private(set) var duckOthersForPrompts: Bool

    @ObservationIgnored private var listeners: [@MainActor (AudioSessionEvent) -> Void] = []
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []
    @ObservationIgnored private let session = AVAudioSession.sharedInstance()

    init(microphonePreference: MicrophonePreference, duckOthersForPrompts: Bool) {
        self.microphonePreference = microphonePreference
        self.duckOthersForPrompts = duckOthersForPrompts
        installObservers()
        refreshRoute()
    }

    var planner: SessionPlanner {
        SessionPlanner(microphonePreference: microphonePreference, duckOthersForPrompts: duckOthersForPrompts)
    }

    func addListener(_ listener: @escaping @MainActor (AudioSessionEvent) -> Void) {
        listeners.append(listener)
    }

    // MARK: Demands

    func acquire(_ demand: AudioDemand) throws {
        var next = activeDemands
        next.insert(demand)
        let plan = try planner.plan(for: next)
        do {
            try apply(plan)
        } catch {
            lastError = "\(demand.rawValue): \(error.localizedDescription)"
            throw error
        }
        activeDemands = next
    }

    func release(_ demand: AudioDemand) {
        guard activeDemands.contains(demand) else { return }
        var next = activeDemands
        next.remove(demand)
        activeDemands = next
        do {
            try apply(try planner.plan(for: next))
        } catch {
            lastError = "Release \(demand.rawValue): \(error.localizedDescription)"
        }
    }

    func setMicrophonePreference(_ preference: MicrophonePreference) {
        guard preference != microphonePreference else { return }
        microphonePreference = preference
        reapply()
    }

    func setDuckOthersForPrompts(_ duck: Bool) {
        guard duck != duckOthersForPrompts else { return }
        duckOthersForPrompts = duck
        reapply()
    }

    private func reapply() {
        guard !activeDemands.isEmpty else { return }
        do {
            try apply(try planner.plan(for: activeDemands))
        } catch {
            lastError = "Reconfigure: \(error.localizedDescription)"
        }
    }

    private func apply(_ plan: SessionPlan?) throws {
        guard let plan else {
            if isSessionActive {
                do {
                    try session.setActive(false, options: .notifyOthersOnDeactivation)
                    isSessionActive = false
                } catch {
                    // Typically "session deactivated while I/O is running"; it stays active.
                    lastError = "Deactivate: \(error.localizedDescription)"
                }
            }
            appliedPlan = nil
            refreshRoute()
            return
        }
        let changed = plan != appliedPlan
        if changed {
            try session.setCategory(plan.category, mode: plan.mode, options: plan.options)
        }
        if !isSessionActive {
            try session.setActive(true)
            isSessionActive = true
        }
        if changed {
            applyPreferredInput(plan.preferredInput)
        }
        appliedPlan = plan
        lastError = nil
        refreshRoute()
    }

    private func applyPreferredInput(_ kind: PreferredInputKind?) {
        let inputs = session.availableInputs ?? []
        let port: AVAudioSessionPortDescription?
        switch kind {
        case nil:
            port = nil
        case .builtInMicrophone:
            port = inputs.first { $0.portType == .builtInMic }
        case .bluetooth:
            port = inputs.first {
                $0.bluetoothMicrophoneExtension != nil || $0.portType == .bluetoothHFP || $0.portType == .bluetoothLE
            }
        }
        do {
            try session.setPreferredInput(port)
        } catch {
            lastError = "Preferred input: \(error.localizedDescription)"
        }
    }

    // MARK: Route state

    func refreshRoute() {
        let current = session.currentRoute
        route = AudioRouteSnapshot(
            inputs: current.inputs.map(AudioPortInfo.init(port:)),
            outputs: current.outputs.map(AudioPortInfo.init(port:))
        )
        availableInputs = (session.availableInputs ?? []).map(AudioPortInfo.init(port:))
        details = SessionDetails(
            category: session.category.rawValue.replacingOccurrences(of: "AVAudioSessionCategory", with: ""),
            mode: session.mode.rawValue.replacingOccurrences(of: "AVAudioSessionMode", with: ""),
            options: Self.describe(session.categoryOptions),
            sampleRate: session.sampleRate,
            ioBufferDuration: session.ioBufferDuration,
            inputLatency: session.inputLatency,
            outputLatency: session.outputLatency,
            isOtherAudioPlaying: session.isOtherAudioPlaying,
            preferredInput: session.preferredInput?.portName
        )
    }

    /// Rider-facing explanation when the active input differs from the requested one.
    var inputMismatch: String? {
        guard activeDemands.contains(.microphoneSensing), let input = route.inputs.first else { return nil }
        switch microphonePreference {
        case .automatic:
            return nil
        case .builtIn:
            return input.kind == .builtInMicrophone ? nil : "Requested the iPhone microphone; active input is \(input.name)."
        case .bluetoothHandsFree, .bluetoothHighQuality:
            return input.kind.isBluetooth || input.highQualityRecording != nil ? nil
                : "Requested a Bluetooth microphone; active input is \(input.name). Connect a headset with a microphone."
        }
    }

    /// Status of iOS 26 high-quality Bluetooth recording for the active input.
    var highQualityRecordingStatus: String {
        guard let input = route.inputs.first else { return "No active input" }
        guard let hq = input.highQualityRecording else { return "Not a Bluetooth microphone" }
        if hq.enabled { return "Enabled" }
        return hq.supported ? "Supported, not enabled" : "Not supported by this device"
    }

    // MARK: Notifications

    private func installObservers() {
        let center = NotificationCenter.default

        tokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] note in
            let reasonValue = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let previous = (note.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription)?
                .outputs.map(AudioPortInfo.init(port:)) ?? []
            MainActor.assumeIsolated {
                self?.handleRouteChange(reasonValue: reasonValue, previousOutputs: previous)
            }
        })

        // Legacy interruption notification. Deprecated in iOS 27 in favour of the
        // inactive/resumption notifications below; both are observed and handled idempotently
        // until device testing confirms the iOS 27 behaviour.
        tokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsValue = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            let reasonValue = note.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt
            MainActor.assumeIsolated {
                self?.handleLegacyInterruption(typeValue: typeValue, optionsValue: optionsValue, reasonValue: reasonValue)
            }
        })

        if #available(iOS 27.0, *) {
            tokens.append(center.addObserver(forName: AVAudioSession.didBecomeInactiveNotification, object: session, queue: .main) { [weak self] note in
                let context = note.userInfo?[AVAudioSession.deactivationContextKey] as? AVAudioSession.DeactivationContext
                guard context?.source == .system else { return }
                let reason = Self.describe(interruptionReason: context?.interruptionContext?.reason)
                MainActor.assumeIsolated { self?.interruptionBegan(reason: reason) }
            })
            tokens.append(center.addObserver(forName: AVAudioSession.resumptionRecommendationNotification, object: session, queue: .main) { [weak self] note in
                let context = note.userInfo?[AVAudioSession.resumptionContextKey] as? AVAudioSession.ResumptionContext
                let shouldResume = context?.recommendation == .shouldResume
                MainActor.assumeIsolated { self?.interruptionEnded(shouldResume: shouldResume) }
            })
        }

        tokens.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMediaServicesReset() }
        })

        tokens.append(center.addObserver(forName: AVAudioSession.availableInputsChangeNotification, object: session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshRoute() }
        })
    }

    private func emit(_ event: AudioSessionEvent) {
        for listener in listeners { listener(event) }
    }

    private func handleRouteChange(reasonValue: UInt?, previousOutputs: [AudioPortInfo]) {
        let reason = reasonValue.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
        let text = RouteChangeAnalyzer.describe(reason)
        lastRouteChange = RouteChangeRecord(reason: text, at: Date())
        refreshRoute()
        emit(.routeChanged(reason: text))
        if RouteChangeAnalyzer.lostPrivateOutput(reason: reason, previousOutputs: previousOutputs, currentOutputs: route.outputs) {
            emit(.privateOutputLost(previousOutput: previousOutputs.map(\.name).joined(separator: ", ")))
        }
    }

    private func handleLegacyInterruption(typeValue: UInt?, optionsValue: UInt?, reasonValue: UInt?) {
        guard let typeValue, let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            let reason = reasonValue.flatMap(AVAudioSession.InterruptionReason.init(rawValue:))
            interruptionBegan(reason: Self.describe(interruptionReason: reason))
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue ?? 0)
            interruptionEnded(shouldResume: options.contains(.shouldResume))
        @unknown default:
            break
        }
    }

    private func interruptionBegan(reason: String) {
        guard !isInterrupted else { return }
        isInterrupted = true
        isSessionActive = false
        lastInterruptionReason = reason
        refreshRoute()
        emit(.interruptionBegan(reason: reason))
    }

    private func interruptionEnded(shouldResume: Bool) {
        guard isInterrupted else { return }
        isInterrupted = false
        refreshRoute()
        emit(.interruptionEnded(shouldResume: shouldResume))
    }

    private func handleMediaServicesReset() {
        // All session state is lost; reapply on the next acquire from each feature.
        isSessionActive = false
        appliedPlan = nil
        isInterrupted = false
        let demands = activeDemands
        activeDemands = []
        lastError = "Media services were reset"
        for demand in demands where demand != .spokenPrompt && demand != .samplePlayback {
            try? acquire(demand)
        }
        emit(.mediaServicesReset)
    }

    // MARK: Descriptions

    nonisolated static func describe(interruptionReason: AVAudioSession.InterruptionReason?) -> String {
        switch interruptionReason {
        case .builtInMicMuted: "Built-in microphone muted"
        case .routeDisconnected: "Audio route disconnected"
        case .default, .none: "Another app or a call took audio"
        default: "Audio interrupted"
        }
    }

    static func describe(_ options: AVAudioSession.CategoryOptions) -> String {
        var names: [String] = []
        if options.contains(.mixWithOthers) { names.append("mixWithOthers") }
        if options.contains(.duckOthers) { names.append("duckOthers") }
        if options.contains(.allowBluetoothHFP) { names.append("allowBluetoothHFP") }
        if options.contains(.allowBluetoothA2DP) { names.append("allowBluetoothA2DP") }
        if options.contains(.defaultToSpeaker) { names.append("defaultToSpeaker") }
        if options.contains(.interruptSpokenAudioAndMixWithOthers) { names.append("interruptSpokenAudio") }
        if options.contains(.bluetoothHighQualityRecording) { names.append("bluetoothHighQualityRecording") }
        return names.isEmpty ? "none" : names.joined(separator: ", ")
    }
}
