import AVFAudio
import Foundation

/// App-level classification of an `AVAudioSession.Port`.
enum PortKind: String, Sendable, Equatable {
    case builtInMicrophone
    case builtInSpeaker
    case builtInReceiver
    case wiredHeadphones
    case wiredHeadsetMicrophone
    case bluetoothHandsFree
    case bluetoothA2DP
    case bluetoothLE
    case usb
    case carAudio
    case airPlay
    case other

    init(portType: AVAudioSession.Port) {
        switch portType {
        case .builtInMic: self = .builtInMicrophone
        case .builtInSpeaker: self = .builtInSpeaker
        case .builtInReceiver: self = .builtInReceiver
        case .headphones: self = .wiredHeadphones
        case .headsetMic: self = .wiredHeadsetMicrophone
        case .bluetoothHFP: self = .bluetoothHandsFree
        case .bluetoothA2DP: self = .bluetoothA2DP
        case .bluetoothLE: self = .bluetoothLE
        case .usbAudio: self = .usb
        case .carAudio: self = .carAudio
        case .airPlay: self = .airPlay
        default: self = .other
        }
    }

    var isBluetooth: Bool {
        switch self {
        case .bluetoothHandsFree, .bluetoothA2DP, .bluetoothLE: true
        default: false
        }
    }

    /// Output that only the rider hears (headphones). Speaker, car and AirPlay are not private.
    var isPrivateListening: Bool {
        switch self {
        case .wiredHeadphones, .bluetoothHandsFree, .bluetoothA2DP, .bluetoothLE: true
        default: false
        }
    }

    var displayName: String {
        switch self {
        case .builtInMicrophone: "iPhone microphone"
        case .builtInSpeaker: "iPhone speaker"
        case .builtInReceiver: "iPhone receiver"
        case .wiredHeadphones: "Wired headphones"
        case .wiredHeadsetMicrophone: "Wired headset microphone"
        case .bluetoothHandsFree: "Bluetooth hands-free (HFP)"
        case .bluetoothA2DP: "Bluetooth audio (A2DP)"
        case .bluetoothLE: "Bluetooth LE audio"
        case .usb: "USB audio"
        case .carAudio: "Car audio"
        case .airPlay: "AirPlay"
        case .other: "Other"
        }
    }
}

/// Supported/enabled state of a Bluetooth microphone capability (iOS 26+).
struct CapabilityState: Sendable, Equatable {
    let supported: Bool
    let enabled: Bool
}

/// Value snapshot of one audio port.
struct AudioPortInfo: Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let portType: String
    let kind: PortKind
    let channelCount: Int
    /// `nil` when the port has no Bluetooth microphone extension.
    let highQualityRecording: CapabilityState?
    let farFieldCapture: CapabilityState?

    init(id: String, name: String, portType: String, kind: PortKind, channelCount: Int = 1,
         highQualityRecording: CapabilityState? = nil, farFieldCapture: CapabilityState? = nil) {
        self.id = id
        self.name = name
        self.portType = portType
        self.kind = kind
        self.channelCount = channelCount
        self.highQualityRecording = highQualityRecording
        self.farFieldCapture = farFieldCapture
    }

    init(port: AVAudioSessionPortDescription) {
        let bluetoothMic = port.bluetoothMicrophoneExtension
        self.init(
            id: port.uid,
            name: port.portName,
            portType: port.portType.rawValue,
            kind: PortKind(portType: port.portType),
            channelCount: port.channels?.count ?? 0,
            highQualityRecording: bluetoothMic.map {
                CapabilityState(supported: $0.highQualityRecording.isSupported, enabled: $0.highQualityRecording.isEnabled)
            },
            farFieldCapture: bluetoothMic.map {
                CapabilityState(supported: $0.farFieldCapture.isSupported, enabled: $0.farFieldCapture.isEnabled)
            }
        )
    }

    var summary: String { "\(name) · \(kind.displayName)" }
}

struct AudioRouteSnapshot: Sendable, Equatable {
    var inputs: [AudioPortInfo]
    var outputs: [AudioPortInfo]

    static let empty = AudioRouteSnapshot(inputs: [], outputs: [])

    var inputSummary: String { inputs.isEmpty ? "No input" : inputs.map(\.summary).joined(separator: ", ") }
    var outputSummary: String { outputs.isEmpty ? "No output" : outputs.map(\.summary).joined(separator: ", ") }
    var outputIsPrivate: Bool { outputs.contains { $0.kind.isPrivateListening } }
}

/// Pure analysis of route changes, kept separate from AVAudioSession for testing.
enum RouteChangeAnalyzer {
    /// `true` when private listening output (headphones) was lost and audio now plays elsewhere.
    static func lostPrivateOutput(
        reason: AVAudioSession.RouteChangeReason?,
        previousOutputs: [AudioPortInfo],
        currentOutputs: [AudioPortInfo]
    ) -> Bool {
        guard reason == .oldDeviceUnavailable else { return false }
        let hadPrivate = previousOutputs.contains { $0.kind.isPrivateListening }
        let hasPrivate = currentOutputs.contains { $0.kind.isPrivateListening }
        return hadPrivate && !hasPrivate
    }

    static func describe(_ reason: AVAudioSession.RouteChangeReason?) -> String {
        switch reason {
        case .newDeviceAvailable: "New device available"
        case .oldDeviceUnavailable: "Device disconnected"
        case .categoryChange: "Category changed"
        case .override: "Route overridden"
        case .wakeFromSleep: "Woke from sleep"
        case .noSuitableRouteForCategory: "No suitable route"
        case .routeConfigurationChange: "Route configuration changed"
        case .unknown, .none: "Unknown"
        @unknown default: "Other"
        }
    }
}
