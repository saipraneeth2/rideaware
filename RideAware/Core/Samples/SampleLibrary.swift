import AVFAudio
import Foundation
import Observation

struct AudioSample: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let fileName: String
    let recordedAt: Date
    var duration: TimeInterval
    let inputDescription: String
}

/// Consent-gated raw-audio samples for building a dataset (Milestone 2 adds labelling).
///
/// Nothing is recorded unless the rider has turned on recording consent *and* starts a
/// recording. Files stay on the device, are excluded from backup, and can be deleted
/// individually or all at once. Turning consent off stops any recording in progress.
@MainActor
@Observable
final class SampleLibrary {
    enum SampleError: LocalizedError {
        case consentRequired
        case microphoneNotRunning

        var errorDescription: String? {
            switch self {
            case .consentRequired: "Turn on sample-collection consent in Settings first."
            case .microphoneNotRunning: "Start a ride or the microphone test first."
            }
        }
    }

    private(set) var samples: [AudioSample] = []
    private(set) var isRecording = false
    private(set) var recordingStartedAt: Date?
    private(set) var lastError: String?
    let maxDuration: TimeInterval = 15

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let microphone: MicrophoneMonitor
    @ObservationIgnored private let hasConsent: @MainActor () -> Bool
    @ObservationIgnored private var autoStop: Task<Void, Never>?
    @ObservationIgnored private var pending: AudioSample?

    init(directory: URL, microphone: MicrophoneMonitor, hasConsent: @escaping @MainActor () -> Bool) {
        self.directory = directory
        self.microphone = microphone
        self.hasConsent = hasConsent
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(values)
        loadIndex()
    }

    static func defaultDirectory() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("RideAware/Samples", isDirectory: true)
    }

    func url(for sample: AudioSample) -> URL {
        directory.appendingPathComponent(sample.fileName)
    }

    var totalBytes: Int64 {
        samples.reduce(0) { total, sample in
            let size = (try? FileManager.default.attributesOfItem(atPath: url(for: sample).path)[.size] as? Int64) ?? 0
            return total + size
        }
    }

    func startRecording() {
        guard !isRecording else { return }
        guard hasConsent() else { lastError = SampleError.consentRequired.localizedDescription; return }
        guard microphone.isRunning else { lastError = SampleError.microphoneNotRunning.localizedDescription; return }
        let id = UUID()
        let fileName = "sample-\(id.uuidString).caf"
        do {
            try microphone.beginSampleRecording(to: directory.appendingPathComponent(fileName))
        } catch {
            lastError = error.localizedDescription
            return
        }
        let start = Date()
        pending = AudioSample(id: id, fileName: fileName, recordedAt: start, duration: 0, inputDescription: microphone.inputDescription)
        isRecording = true
        recordingStartedAt = start
        lastError = nil
        autoStop = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(self?.maxDuration ?? 15))
            guard !Task.isCancelled else { return }
            self?.stopRecording()
        }
    }

    func stopRecording() {
        autoStop?.cancel()
        autoStop = nil
        guard isRecording else { return }
        isRecording = false
        recordingStartedAt = nil
        let result = microphone.finishSampleRecording()
        if var sample = pending {
            sample.duration = result?.duration ?? 0
            if result != nil {
                samples.insert(sample, at: 0)
                saveIndex()
            } else {
                lastError = "Recording ended without audio (the microphone stopped)."
                try? FileManager.default.removeItem(at: url(for: sample))
            }
        }
        pending = nil
    }

    /// Called when consent is withdrawn.
    func consentWithdrawn() {
        stopRecording()
    }

    func delete(_ sample: AudioSample) {
        try? FileManager.default.removeItem(at: url(for: sample))
        samples.removeAll { $0.id == sample.id }
        saveIndex()
    }

    func deleteAll() {
        stopRecording()
        for sample in samples { try? FileManager.default.removeItem(at: url(for: sample)) }
        samples.removeAll()
        saveIndex()
    }

    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        samples = (try? decoder.decode([AudioSample].self, from: data)) ?? []
        samples.removeAll { !FileManager.default.fileExists(atPath: url(for: $0).path) }
    }

    private func saveIndex() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(samples).write(to: indexURL, options: .atomic)
    }
}

/// Plays a recorded sample through the coordinator-managed session.
@MainActor
@Observable
final class SamplePlayer: NSObject {
    private(set) var playingID: UUID?
    private(set) var lastError: String?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private let coordinator: AudioSessionCoordinator

    init(coordinator: AudioSessionCoordinator) {
        self.coordinator = coordinator
    }

    func play(_ sample: AudioSample, from library: SampleLibrary) {
        stop()
        do {
            try coordinator.acquire(.samplePlayback)
            let player = try AVAudioPlayer(contentsOf: library.url(for: sample))
            player.delegate = self
            player.play()
            self.player = player
            playingID = sample.id
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            coordinator.release(.samplePlayback)
        }
    }

    func stop() {
        player?.stop()
        player = nil
        if playingID != nil {
            playingID = nil
            coordinator.release(.samplePlayback)
        }
    }
}

extension SamplePlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.stop() }
    }
}
