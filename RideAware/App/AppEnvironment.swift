import Foundation
import Observation

/// Composition root. Builds every service once and wires their callbacks.
@MainActor
@Observable
final class AppEnvironment {
    let settings: AppSettings
    let audio: AudioSessionCoordinator
    let microphone: MicrophoneMonitor
    let speaker: SpeechAlertSpeaker
    let alerts: AlertCoordinator
    let history: RideHistory
    let group: GroupSession
    let locationSharing: LocationSharingController
    let samples: SampleLibrary
    let samplePlayer: SamplePlayer
    let ride: RideController

    /// Microphone test from Diagnostics, outside a ride.
    private(set) var isMicrophoneTestRunning = false

    init(settings: AppSettings, rideStore: any RideStoring, samplesDirectory: URL) {
        self.settings = settings

        let audio = AudioSessionCoordinator(
            microphonePreference: settings.microphonePreference,
            duckOthersForPrompts: settings.duckOthersForPrompts
        )
        let microphone = MicrophoneMonitor(coordinator: audio, permissions: SystemMicrophonePermission())
        let speaker = SpeechAlertSpeaker(coordinator: audio)
        let alerts = AlertCoordinator(speaker: speaker)
        let history = RideHistory(store: rideStore)
        let group = GroupSession(localRider: RiderIdentity(id: settings.riderID, displayName: settings.riderDisplayName))
        let locationSharing = LocationSharingController(provider: UnavailableLocationProvider(), transportAvailable: false)
        let samples = SampleLibrary(directory: samplesDirectory, microphone: microphone) { [settings] in settings.recordingConsent }
        let ride = RideController(
            microphone: microphone,
            alerts: alerts,
            history: history,
            locationSharing: locationSharing,
            group: group,
            makeDetector: RideController.makeDefaultDetector
        )

        alerts.isSpeechAllowed = { [settings, audio] category in
            guard settings.spokenAlertsEnabled else { return false }
            switch category {
            case .health: guard settings.spokenHealthAlertsEnabled else { return false }
            case .group: guard settings.spokenGroupMessagesEnabled else { return false }
            case .detection, .ride, .test: break
            }
            return settings.allowSpeakerFallback || audio.route.outputIsPrivate
        }

        group.onRemoteReport = { [alerts] report in
            alerts.notify(.groupReport(senderName: report.sender.displayName, kind: report.kind), category: .group)
        }
        group.onJoin = { [locationSharing] in locationSharing.groupDidJoin() }
        group.onLeave = { [locationSharing] in locationSharing.groupDidLeave() }

        audio.addListener { [ride, alerts] event in
            guard ride.isRiding else { return }
            switch event {
            case .privateOutputLost(let previous):
                ride.recordIncident("Headphones disconnected (\(previous))")
                alerts.notify(.headphonesDisconnected, category: .health)
            case .interruptionBegan(let reason):
                ride.recordIncident("Audio interrupted: \(reason)")
            case .interruptionEnded:
                ride.recordIncident("Audio interruption ended")
            case .mediaServicesReset:
                ride.recordIncident("Media services reset")
            case .routeChanged:
                break
            }
        }

        self.audio = audio
        self.microphone = microphone
        self.speaker = speaker
        self.alerts = alerts
        self.history = history
        self.group = group
        self.locationSharing = locationSharing
        self.samples = samples
        self.samplePlayer = SamplePlayer(coordinator: audio)
        self.ride = ride
    }

    static func live() -> AppEnvironment {
        let settings = AppSettings()
        let storeURL = (try? JSONFileRideStore.defaultURL())
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("rides.json")
        return AppEnvironment(
            settings: settings,
            rideStore: JSONFileRideStore(url: storeURL),
            samplesDirectory: SampleLibrary.defaultDirectory()
        )
    }

    func startRide() async {
        if isMicrophoneTestRunning { stopMicrophoneTest() }
        await ride.start(RideConfiguration(
            detector: settings.detectorChoice,
            microphoneEnabled: settings.microphoneEnabled,
            microphonePreference: settings.microphonePreference
        ))
    }

    func stopRide() {
        samples.stopRecording()
        ride.stop()
    }

    func startMicrophoneTest() async {
        guard !ride.isRiding, !isMicrophoneTestRunning else { return }
        isMicrophoneTestRunning = true
        await microphone.start()
    }

    func stopMicrophoneTest() {
        guard isMicrophoneTestRunning else { return }
        samples.stopRecording()
        microphone.stop()
        isMicrophoneTestRunning = false
    }

    func applyAudioPreferences() {
        audio.setMicrophonePreference(settings.microphonePreference)
        audio.setDuckOthersForPrompts(settings.duckOthersForPrompts)
    }
}
