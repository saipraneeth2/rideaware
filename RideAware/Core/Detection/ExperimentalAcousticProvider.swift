import Foundation

/// Placeholder for experimental acoustic vehicle-sound inference (Milestone 2).
///
/// No validated model ships with this build, so the provider reports itself unavailable and
/// never emits events. It deliberately does **not** fall back to volume thresholds or random
/// values: loudness is not vehicle detection.
///
/// The first candidate to evaluate is Apple's built-in SoundAnalysis classifier
/// (`SNClassifierIdentifier.version1`), whose label set includes `car_passing_by`, `engine`,
/// `truck`, `motorcycle` and `traffic_noise`. It has not been evaluated on cycling audio,
/// with wind noise, or for approach warning lead time. See docs/DATASET_AND_MODEL_PLAN.md.
@MainActor
final class ExperimentalAcousticProvider: DetectionProvider {
    nonisolated static let unavailableReason = "No validated vehicle-sound model in this build"

    let descriptor = DetectorDescriptor(
        kind: .experimentalAcoustic,
        name: "Experimental acoustic detection",
        isSimulated: false,
        summary: "Vehicle-sound inference is not available yet. The microphone runs for audio feasibility measurements only."
    )
    let availability: DetectorAvailability = .unavailable(reason: ExperimentalAcousticProvider.unavailableReason)
    let isRunning = false
    let lastInputAt: Date? = nil
    let failureReason: String? = nil
    var onEvent: (@MainActor (DetectionEvent) -> Void)?

    func start() {}
    func stop() {}
}
