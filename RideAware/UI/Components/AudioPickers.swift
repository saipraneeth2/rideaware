import AVFAudio
import AVKit
import SwiftUI

/// Presents the system microphone picker (`AVInputPickerInteraction`, iOS 26).
/// Selecting an input here sets the session's preferred input; the coordinator observes the
/// resulting route change.
struct SystemInputPickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> UIButton {
        var configuration = UIButton.Configuration.bordered()
        configuration.title = "System microphone picker"
        configuration.image = UIImage(systemName: "mic.badge.plus")
        configuration.imagePadding = 8
        let button = UIButton(configuration: configuration)
        button.addInteraction(AVInputPickerInteraction(audioSession: AVAudioSession.sharedInstance()))
        button.addAction(UIAction { action in
            guard let button = action.sender as? UIButton else { return }
            let picker = button.interactions.compactMap { $0 as? AVInputPickerInteraction }.first
            picker?.present()
        }, for: .primaryActionTriggered)
        button.accessibilityLabel = "Choose microphone input"
        button.accessibilityHint = "Opens the system list of available microphones"
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {}
}

/// System output route picker (AirPods, speaker, etc.).
struct OutputRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.accessibilityLabel = "Choose audio output"
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
