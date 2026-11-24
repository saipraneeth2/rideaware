import AVFAudio
import Foundation

enum MicrophonePermissionState: String, Sendable {
    case undetermined
    case denied
    case granted

    var label: String {
        switch self {
        case .undetermined: "Not requested"
        case .denied: "Denied"
        case .granted: "Granted"
        }
    }
}

@MainActor
protocol MicrophonePermissionProviding: AnyObject {
    var state: MicrophonePermissionState { get }
    func request() async -> Bool
}

/// Real record permission via `AVAudioApplication` (iOS 17+).
@MainActor
final class SystemMicrophonePermission: MicrophonePermissionProviding {
    var state: MicrophonePermissionState {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        case .undetermined: .undetermined
        @unknown default: .undetermined
        }
    }

    func request() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}
