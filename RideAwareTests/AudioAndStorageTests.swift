import AVFAudio
import Foundation
import Testing
@testable import RideAware

@Suite("Audio session planning: one plan for all demands")
struct SessionPlannerTests {
    let planner = SessionPlanner(microphonePreference: .automatic, duckOthersForPrompts: true)

    @Test func noDemandsMeansInactiveSession() throws {
        #expect(try planner.plan(for: []) == nil)
    }

    @Test func voiceChatAndSensingConflict() {
        #expect(throws: SessionPlanError.self) { try planner.plan(for: [.voiceChat, .microphoneSensing]) }
    }

    @Test func promptsDoNotReconfigureSensing() throws {
        let sensing = try planner.plan(for: [.microphoneSensing])
        #expect(try planner.plan(for: [.microphoneSensing, .spokenPrompt]) == sensing)
        #expect(try planner.plan(for: [.microphoneSensing, .samplePlayback]) == sensing)
    }

    @Test func sensingIsMixableRecordingWithoutDucking() throws {
        let plan = try #require(try planner.plan(for: [.microphoneSensing]))
        #expect(plan.category == .playAndRecord)
        #expect(plan.mode == .default)
        #expect(plan.options.contains(.mixWithOthers))
        #expect(plan.options.contains(.allowBluetoothA2DP))
        #expect(!plan.options.contains(.duckOthers))
        #expect(!plan.options.contains(.allowBluetoothHFP))
    }

    @Test func promptOnlyUsesVoicePromptAndDucksWhenEnabled() throws {
        let plan = try #require(try planner.plan(for: [.spokenPrompt]))
        #expect(plan.category == .playback)
        #expect(plan.mode == .voicePrompt)
        #expect(plan.options.contains(.duckOthers))
        let noDuck = SessionPlanner(microphonePreference: .automatic, duckOthersForPrompts: false)
        #expect(try noDuck.plan(for: [.spokenPrompt])?.options.contains(.duckOthers) == false)
    }

    @Test func highQualityBluetoothUsesDefaultModeWithHFPFallback() throws {
        let hq = SessionPlanner(microphonePreference: .bluetoothHighQuality, duckOthersForPrompts: true)
        let plan = try #require(try hq.plan(for: [.microphoneSensing]))
        #expect(plan.mode == .default)
        #expect(plan.options.contains(.bluetoothHighQualityRecording))
        #expect(plan.options.contains(.allowBluetoothHFP))
        #expect(plan.preferredInput == .bluetooth)
    }

    @Test func builtInPreferenceForcesBuiltInMic() throws {
        let builtIn = SessionPlanner(microphonePreference: .builtIn, duckOthersForPrompts: true)
        #expect(try builtIn.plan(for: [.microphoneSensing])?.preferredInput == .builtInMicrophone)
    }
}

@Suite("Route changes")
struct RouteChangeTests {
    let airpods = AudioPortInfo(id: "a", name: "AirPods", portType: "BluetoothA2DPOutput", kind: .bluetoothA2DP)
    let speaker = AudioPortInfo(id: "s", name: "Speaker", portType: "Speaker", kind: .builtInSpeaker)
    let wired = AudioPortInfo(id: "w", name: "Headphones", portType: "Headphones", kind: .wiredHeadphones)

    @Test func headphoneDisconnectToSpeakerIsDetected() {
        #expect(RouteChangeAnalyzer.lostPrivateOutput(reason: .oldDeviceUnavailable, previousOutputs: [airpods], currentOutputs: [speaker]))
    }

    @Test func switchingBetweenHeadphonesIsNotLoss() {
        #expect(!RouteChangeAnalyzer.lostPrivateOutput(reason: .oldDeviceUnavailable, previousOutputs: [airpods], currentOutputs: [wired]))
    }

    @Test func otherReasonsAreNotLoss() {
        #expect(!RouteChangeAnalyzer.lostPrivateOutput(reason: .newDeviceAvailable, previousOutputs: [airpods], currentOutputs: [speaker]))
        #expect(!RouteChangeAnalyzer.lostPrivateOutput(reason: .oldDeviceUnavailable, previousOutputs: [speaker], currentOutputs: [speaker]))
    }

    @Test func portClassification() {
        #expect(PortKind(portType: .bluetoothHFP).isBluetooth)
        #expect(PortKind(portType: .bluetoothA2DP).isPrivateListening)
        #expect(!PortKind(portType: .builtInSpeaker).isPrivateListening)
        #expect(!PortKind(portType: .carAudio).isPrivateListening)
    }
}

@Suite("Level meter (loudness only, never detection)")
struct LevelMeterTests {
    @Test func silenceIsFloor() {
        #expect(LevelMeter.measure([Float](repeating: 0, count: 512)) == InputLevel(rmsDBFS: LevelMeter.floorDB, peakDBFS: LevelMeter.floorDB))
    }

    @Test func fullScaleSineIsAboutMinus3dB() {
        let sine = (0..<4800).map { Float(sin(2 * Double.pi * 1000 * Double($0) / 48000)) }
        let level = LevelMeter.measure(sine)
        #expect(abs(level.rmsDBFS - (-3.01)) < 0.05)
        #expect(abs(level.peakDBFS) < 0.01)
    }

    @Test func halfAmplitudeIsMinus6dB() {
        let level = LevelMeter.measure([Float](repeating: 0.5, count: 100))
        #expect(abs(level.rmsDBFS - (-6.02)) < 0.01)
    }
}

@Suite("Spoken wording")
struct AlertPhraseTests {
    static var allPhrases: [AlertPhrase] {
        var phrases: [AlertPhrase] = [.rideEnded, .monitoringResumed, .headphonesDisconnected, .testPrompt,
                                      .rideStarted(.monitoring), .rideStarted(.simulation), .rideStarted(.detectionUnavailable),
                                      .monitoringStopped(reason: ""),
                                      .monitoringStopped(reason: ExperimentalAcousticProvider.unavailableReason),
                                      .monitoringStopped(reason: "Detector input is stale"),
                                      .monitoringStopped(reason: "Simulated sensor failure")]
        for kind in DetectionKind.allCases {
            phrases.append(.detection(kind, simulated: true))
            phrases.append(.detection(kind, simulated: false))
        }
        for kind in GroupReportKind.allCases {
            phrases.append(.groupReport(senderName: "Alex", kind: kind))
        }
        return phrases
    }

    @Test(arguments: allPhrases)
    func noSafetyDistanceOrDirectionClaims(_ phrase: AlertPhrase) {
        let text = phrase.text.lowercased()
        for fragment in AlertPhrase.prohibitedFragments {
            #expect(!text.contains(fragment), "\"\(phrase.text)\" contains \"\(fragment)\"")
        }
    }

    @Test func acousticDetectionUsesConservativeLabel() {
        #expect(AlertPhrase.detection(.possibleVehicleSound, simulated: false).text == "Possible vehicle sound.")
        #expect(AlertPhrase.detection(.possibleVehicleSound, simulated: true).text == "Simulation. Possible vehicle sound.")
    }
}

@MainActor
@Suite("Local ride storage")
struct RideStorageTests {
    @Test func jsonStoreRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONFileRideStore(url: directory.appendingPathComponent("rides.json"))

        var ride = RideSession(id: UUID(), startedAt: Date(timeIntervalSince1970: 1_000), detectorName: "Sim",
                               detectorIsSimulated: true, microphoneEnabled: true, microphonePreference: .builtIn)
        ride.endedAt = Date(timeIntervalSince1970: 1_600)
        ride.counts.announced = 3
        ride.healthIncidents = [HealthIncident(at: Date(timeIntervalSince1970: 1_100), summary: "Headphones disconnected")]

        let history = RideHistory(store: store)
        history.record(ride)
        let reloaded = RideHistory(store: store)
        #expect(reloaded.rides == [ride])
        #expect(reloaded.rides[0].duration == 600)

        reloaded.deleteAll()
        #expect(try store.load().isEmpty)
    }

    @Test func missingFileLoadsEmpty() throws {
        let store = JSONFileRideStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json"))
        #expect(try store.load().isEmpty)
    }
}
