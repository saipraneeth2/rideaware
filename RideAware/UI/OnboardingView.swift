import SwiftUI

struct OnboardingView: View {
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "bicycle")
                        .font(.system(size: 48, weight: .semibold))
                        .accessibilityHidden(true)
                    Text("RideAware")
                        .font(.largeTitle.bold())
                    Text("An experimental awareness aid for cyclists.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                point("What it is", "speaker.wave.2.fill",
                      "Short spoken alerts through your headphones, and private group rides with explicit messages like Slowing or Hazard reported.")

                point("What it is not", "exclamationmark.shield.fill",
                      "It does not prevent collisions and cannot guarantee that a vehicle will be noticed. Silence never means the road is safe. Keep looking and listening as you normally would.")

                point("Vehicle detection is not available yet", "waveform.badge.exclamationmark",
                      "This build has no validated vehicle-sound model. The microphone runs only to measure audio quality for research. Simulation mode produces events that are clearly labelled as not real.")

                point("Existing products", "dot.radiowaves.right",
                      "Radar-based headphone warnings and group intercoms already exist. RideAware is a research prototype asking whether useful acoustic awareness can work without extra hardware.")

                point("Privacy", "lock.fill",
                      "Audio is processed on this iPhone. Nothing is recorded or uploaded unless you turn on sample collection in Settings, and you can delete samples at any time.")

                point("Microphone permission", "mic.fill",
                      "iOS asks for microphone access the first time you start a ride or the microphone test. You can ride without it; the app will show that the microphone is unavailable.")

                Button(action: onContinue) {
                    Text("I understand these limitations")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
                .buttonStyle(.borderedProminent)
                .tint(RideAwareColors.start)
                .foregroundStyle(.white)
                .accessibilityHint("Opens the ride screen")
            }
            .padding(24)
        }
    }

    private func point(_ title: String, _ systemImage: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.body).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    OnboardingView {}
}
