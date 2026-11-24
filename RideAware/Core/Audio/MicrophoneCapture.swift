import AVFAudio
import Foundation

struct InputLevel: Sendable, Equatable {
    /// Root-mean-square level in dBFS. This is loudness, not detection.
    let rmsDBFS: Float
    let peakDBFS: Float
}

struct CaptureFormat: Sendable, Equatable {
    let sampleRate: Double
    let channelCount: Int

    var description: String {
        String(format: "%.0f Hz · %d ch", sampleRate, channelCount)
    }
}

struct CaptureFrameInfo: Sendable {
    let level: InputLevel
    let frameCount: Int
    let receivedAt: Date
}

/// Level metering on raw samples. Pure.
enum LevelMeter {
    static let floorDB: Float = -160

    static func measure(_ samples: UnsafeBufferPointer<Float>) -> InputLevel {
        guard !samples.isEmpty else { return InputLevel(rmsDBFS: floorDB, peakDBFS: floorDB) }
        var sumSquares: Float = 0
        var peak: Float = 0
        for sample in samples {
            sumSquares += sample * sample
            peak = max(peak, abs(sample))
        }
        let rms = (sumSquares / Float(samples.count)).squareRoot()
        return InputLevel(rmsDBFS: toDB(rms), peakDBFS: toDB(peak))
    }

    static func measure(_ samples: [Float]) -> InputLevel {
        samples.withUnsafeBufferPointer { measure($0) }
    }

    static func toDB(_ amplitude: Float) -> Float {
        amplitude > 0 ? max(floorDB, 20 * log10(amplitude)) : floorDB
    }
}

/// Wraps `AVAudioEngine` input capture. It never configures `AVAudioSession`; the
/// `AudioSessionCoordinator` must have activated a recording-capable session first.
///
/// The tap block runs on an audio thread, so this type is not main-actor isolated. Mutable state
/// is protected by `lock`.
final class MicrophoneCapture: @unchecked Sendable {
    enum CaptureError: LocalizedError {
        case noInputAvailable
        case recordingRequiresRunningCapture
        case alreadyRecording

        var errorDescription: String? {
            switch self {
            case .noInputAvailable: "No microphone input is available on the current route."
            case .recordingRequiresRunningCapture: "Start the microphone first."
            case .alreadyRecording: "A sample is already being recorded."
            }
        }
    }

    /// Called on an audio thread for each captured buffer.
    var onFrames: (@Sendable (CaptureFrameInfo) -> Void)?
    /// Called when the engine's I/O configuration changed (route or format) and capture stopped.
    var onConfigurationChange: (@Sendable () -> Void)?

    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?
    private var currentFormat: AVAudioFormat?
    private var sampleFile: AVAudioFile?
    private var sampleURL: URL?

    var isRunning: Bool {
        lock.withLock { engine?.isRunning ?? false }
    }

    @discardableResult
    func start() throws -> CaptureFormat {
        stop()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw CaptureError.noInputAvailable
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        let observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.onConfigurationChange?()
        }
        lock.withLock {
            self.engine = engine
            self.currentFormat = format
            self.configurationObserver = observer
        }
        return CaptureFormat(sampleRate: format.sampleRate, channelCount: Int(format.channelCount))
    }

    func stop() {
        let (engine, observer) = lock.withLock { () -> (AVAudioEngine?, NSObjectProtocol?) in
            let result = (self.engine, self.configurationObserver)
            self.engine = nil
            self.configurationObserver = nil
            self.currentFormat = nil
            return result
        }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        _ = finishRecording()
    }

    // MARK: Consent-gated sample recording (gating is enforced by SampleLibrary)

    func beginRecording(to url: URL) throws {
        try lock.withLock {
            guard let format = currentFormat, engine != nil else { throw CaptureError.recordingRequiresRunningCapture }
            guard sampleFile == nil else { throw CaptureError.alreadyRecording }
            sampleFile = try AVAudioFile(forWriting: url, settings: format.settings,
                                         commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            sampleURL = url
        }
    }

    /// Closes the sample file and returns its URL and duration, if one was open.
    func finishRecording() -> (url: URL, duration: TimeInterval)? {
        lock.withLock {
            defer { sampleFile = nil; sampleURL = nil }
            guard let file = sampleFile, let url = sampleURL else { return nil }
            let duration = file.processingFormat.sampleRate > 0
                ? Double(file.length) / file.processingFormat.sampleRate : 0
            return (url, duration)
        }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        let frameCount = Int(buffer.frameLength)
        let level: InputLevel
        if let channel = buffer.floatChannelData?[0] {
            level = LevelMeter.measure(UnsafeBufferPointer(start: channel, count: frameCount))
        } else {
            level = InputLevel(rmsDBFS: LevelMeter.floorDB, peakDBFS: LevelMeter.floorDB)
        }
        lock.withLock {
            if let sampleFile {
                do { try sampleFile.write(from: buffer) } catch { self.sampleFile = nil }
            }
        }
        onFrames?(CaptureFrameInfo(level: level, frameCount: frameCount, receivedAt: Date()))
    }
}
