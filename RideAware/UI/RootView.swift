import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Group {
            if env.settings.hasCompletedOnboarding {
                MainTabs()
            } else {
                OnboardingView { env.settings.hasCompletedOnboarding = true }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if env.samples.isRecording, let startedAt = env.samples.recordingStartedAt {
                RecordingIndicator(startedAt: startedAt, maxDuration: env.samples.maxDuration) {
                    env.samples.stopRecording()
                }
            }
        }
        .onChange(of: env.settings.microphonePreference) { env.applyAudioPreferences() }
        .onChange(of: env.settings.duckOthersForPrompts) { env.applyAudioPreferences() }
        .onChange(of: env.settings.recordingConsent) { _, consent in
            if !consent { env.samples.consentWithdrawn() }
        }
        .onChange(of: env.settings.riderDisplayName) { _, name in
            env.group.localRider.displayName = name
        }
    }
}

private struct MainTabs: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        TabView {
            Tab("Ride", systemImage: "bicycle") { RideDashboardView() }
            Tab("Group", systemImage: "person.3.fill") { GroupView() }
            Tab("Settings", systemImage: "gearshape.fill") { SettingsView() }
            Tab("Diagnostics", systemImage: "waveform.path.ecg") { DiagnosticsView() }
        }
    }
}
