import AVFAudio
import Foundation

/// A feature's need for the shared audio session. Features declare demands; only
/// `AudioSessionCoordinator` turns the combined demands into session settings.
enum AudioDemand: String, Hashable, Sendable, CaseIterable {
    case microphoneSensing
    case spokenPrompt
    case samplePlayback
    /// Group voice (Milestone 3). Mutually exclusive with sensing until simultaneous operation is
    /// verified on hardware.
    case voiceChat
}

/// Which microphone the rider prefers for sensing.
enum MicrophonePreference: String, Codable, Sendable, CaseIterable, Identifiable {
    case automatic
    case builtIn
    case bluetoothHandsFree
    case bluetoothHighQuality

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .builtIn: "iPhone microphone"
        case .bluetoothHandsFree: "Bluetooth headset (call quality)"
        case .bluetoothHighQuality: "AirPods high-quality recording"
        }
    }

    var detail: String {
        switch self {
        case .automatic:
            "System default input. Bluetooth headphones are used for output only (A2DP), so music quality is preserved."
        case .builtIn:
            "Forces the iPhone microphone. Headphones stay output-only (A2DP)."
        case .bluetoothHandsFree:
            "Uses the headset microphone over Bluetooth HFP. HFP is narrow-band and also lowers playback quality while active."
        case .bluetoothHighQuality:
            "iOS 26 full-bandwidth Bluetooth recording on supported AirPods only. May add input latency, is not for real-time voice, and may be unavailable in some regions. Falls back to HFP when unsupported."
        }
    }
}

enum PreferredInputKind: Sendable, Equatable {
    case builtInMicrophone
    case bluetooth
}

/// Concrete session settings derived from demands.
struct SessionPlan: Equatable, @unchecked Sendable {
    var category: AVAudioSession.Category
    var mode: AVAudioSession.Mode
    var options: AVAudioSession.CategoryOptions
    /// `nil` leaves input selection to the system (or to the rider's choice in the system picker).
    var preferredInput: PreferredInputKind?
}

enum SessionPlanError: LocalizedError, Equatable {
    case conflictingDemands(Set<AudioDemand>)

    var errorDescription: String? {
        switch self {
        case .conflictingDemands:
            "Group voice and microphone sensing cannot run at the same time. They are separate modes until simultaneous use is verified on hardware."
        }
    }
}

/// Pure function from demands to a session plan. No AVAudioSession calls.
struct SessionPlanner: Sendable, Equatable {
    var microphonePreference: MicrophonePreference
    var duckOthersForPrompts: Bool

    func plan(for demands: Set<AudioDemand>) throws -> SessionPlan? {
        if demands.contains(.voiceChat) && demands.contains(.microphoneSensing) {
            throw SessionPlanError.conflictingDemands([.voiceChat, .microphoneSensing])
        }
        if demands.contains(.voiceChat) {
            return SessionPlan(
                category: .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetoothHFP, .defaultToSpeaker],
                preferredInput: nil
            )
        }
        if demands.contains(.microphoneSensing) {
            // Prompts and playback mix into the sensing session; they never reconfigure it.
            return sensingPlan()
        }
        if demands.contains(.spokenPrompt) {
            return SessionPlan(
                category: .playback,
                mode: .voicePrompt,
                options: duckOthersForPrompts ? [.duckOthers, .interruptSpokenAudioAndMixWithOthers] : [.mixWithOthers],
                preferredInput: nil
            )
        }
        if demands.contains(.samplePlayback) {
            return SessionPlan(category: .playback, mode: .default, options: [], preferredInput: nil)
        }
        return nil
    }

    private func sensingPlan() -> SessionPlan {
        // Mixable so the rider's music keeps playing. Ducking is not used while sensing: ducking
        // lasts as long as the session is active, i.e. the whole ride.
        let base: AVAudioSession.CategoryOptions = [.mixWithOthers, .defaultToSpeaker]
        switch microphonePreference {
        case .automatic:
            return SessionPlan(category: .playAndRecord, mode: .default,
                               options: base.union(.allowBluetoothA2DP), preferredInput: nil)
        case .builtIn:
            return SessionPlan(category: .playAndRecord, mode: .default,
                               options: base.union(.allowBluetoothA2DP), preferredInput: .builtInMicrophone)
        case .bluetoothHandsFree:
            return SessionPlan(category: .playAndRecord, mode: .default,
                               options: base.union(.allowBluetoothHFP), preferredInput: .bluetooth)
        case .bluetoothHighQuality:
            // Apple: only compatible with mode .default; HFP is the documented fallback.
            return SessionPlan(category: .playAndRecord, mode: .default,
                               options: base.union([.bluetoothHighQualityRecording, .allowBluetoothHFP]),
                               preferredInput: .bluetooth)
        }
    }
}
