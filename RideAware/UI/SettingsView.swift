import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var confirmDeleteSamples = false
    @State private var showLimitations = false

    var body: some View {
        @Bindable var settings = env.settings
        NavigationStack {
            Form {
                Section {
                    Toggle("Spoken alerts", isOn: $settings.spokenAlertsEnabled)
                    Toggle("Speak monitoring status changes", isOn: $settings.spokenHealthAlertsEnabled)
                        .disabled(!settings.spokenAlertsEnabled)
                    Toggle("Speak group messages", isOn: $settings.spokenGroupMessagesEnabled)
                        .disabled(!settings.spokenAlertsEnabled)
                    Toggle("Use iPhone speaker if headphones disconnect", isOn: $settings.allowSpeakerFallback)
                    Toggle("Lower music during alerts", isOn: $settings.duckOthersForPrompts)
                } header: {
                    Text("Spoken alerts")
                } footer: {
                    Text("Lowering music only works while the microphone is off. During microphone monitoring, alerts mix over music at its current volume, because ducking would last the whole ride.")
                }

                Section("Units") {
                    Picker("Units", selection: $settings.units) {
                        ForEach(DistanceUnits.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Use microphone during rides", isOn: $settings.microphoneEnabled)
                    Picker("Microphone", selection: $settings.microphonePreference) {
                        ForEach(MicrophonePreference.allCases) { Text($0.title).tag($0) }
                    }
                    Text(settings.microphonePreference.detail)
                        .font(.footnote).foregroundStyle(.secondary)
                    LabeledContent("Permission", value: env.microphone.permission.label)
                } header: {
                    Text("Microphone")
                } footer: {
                    Text("The microphone measures audio input for research. It does not detect vehicles in this build.")
                }

                Section {
                    Toggle("I consent to saving audio samples on this iPhone", isOn: $settings.recordingConsent)
                    LabeledContent("Saved samples", value: "\(env.samples.samples.count) · \(ByteCountFormatter.string(fromByteCount: env.samples.totalBytes, countStyle: .file))")
                    Button("Delete all samples", role: .destructive) { confirmDeleteSamples = true }
                        .disabled(env.samples.samples.isEmpty)
                } header: {
                    Text("Recording consent")
                } footer: {
                    Text("Off by default. When on, you can record short clips (max \(Int(env.samples.maxDuration)) s) from Diagnostics while the microphone is running. A red banner shows whenever recording is in progress. Samples stay on this iPhone, are excluded from backups, and are never uploaded. Turning consent off stops any recording.")
                }

                Section("Rider") {
                    TextField("Display name", text: $settings.riderDisplayName)
                }

                Section {
                    Button("Show limitations again") { showLimitations = true }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete all \(env.samples.samples.count) samples?", isPresented: $confirmDeleteSamples, titleVisibility: .visible) {
                Button("Delete all samples", role: .destructive) { env.samples.deleteAll() }
            } message: {
                Text("This permanently removes the audio files from this iPhone.")
            }
            .sheet(isPresented: $showLimitations) {
                OnboardingView { showLimitations = false }
            }
            .onAppear { env.microphone.refreshPermission() }
        }
    }
}
