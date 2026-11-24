import SwiftUI

struct DiagnosticsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        NavigationStack {
            Form {
                SimulationSection()
                FeatureAvailabilitySection()
                AudioSessionSection()
                MicrophoneSection()
                SamplesSection()
                AlertLogSection()
                StoredRidesSection()
            }
            .navigationTitle("Diagnostics")
            .refreshable { env.audio.refreshRoute() }
            .onAppear { env.audio.refreshRoute() }
        }
    }
}

private struct SimulationSection: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var settings = env.settings
        Section {
            Toggle("Simulation mode", isOn: $settings.simulationModeEnabled)
                .disabled(env.ride.isRiding)
            if settings.simulationModeEnabled {
                Toggle("Use radar simulator", isOn: $settings.useRadarSimulator)
                    .disabled(env.ride.isRiding)
                if !settings.useRadarSimulator {
                    Picker("Scenario", selection: $settings.simulationScenario) {
                        ForEach(SimulationScenario.allCases) { Text($0.title).tag($0) }
                    }
                    .disabled(env.ride.isRiding)
                    Text(settings.simulationScenario.detail)
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("Simulation (not real)", systemImage: "theatermasks.fill")
                .foregroundStyle(RideAwareColors.simulation)
        } footer: {
            Text("Simulated events are labelled on screen, prefixed with \"Simulation\" when spoken, and marked as simulated in stored rides. Change scenarios between rides.")
        }
    }
}

private struct FeatureAvailabilitySection: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Section("Feature availability") {
            availability("Acoustic vehicle detection", "Unavailable: no validated model", .critical)
            availability("External radar", "Simulator only; no device supported", .warning)
            availability("Group network transport", "Not configured; local only", .warning)
            availability("Group voice", "Not implemented (Milestone 3)", .warning)
            availability("Location sharing", "Requires network transport", .warning)
            availability("AirPods high-quality recording", env.audio.highQualityRecordingStatus,
                         env.audio.highQualityRecordingStatus == "Enabled" ? .ok : .info)
            availability("Background operation", "Audio background mode set; verify on device", .info)
        }
    }

    private func availability(_ title: String, _ value: String, _ severity: StreamHealth.Severity) -> some View {
        LabeledContent(title) {
            Text(value).foregroundStyle(severity == .info ? .secondary : severity.color)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct AudioSessionSection: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let audio = env.audio
        let details = audio.details
        Section {
            LabeledContent("Active", value: audio.isSessionActive ? "Yes" : "No")
            LabeledContent("Demands", value: audio.activeDemands.isEmpty ? "None" : audio.activeDemands.map(\.rawValue).sorted().joined(separator: ", "))
            LabeledContent("Category", value: details.category)
            LabeledContent("Mode", value: details.mode)
            LabeledContent("Options") { Text(details.options).multilineTextAlignment(.trailing) }
            LabeledContent("Sample rate", value: String(format: "%.0f Hz", details.sampleRate))
            LabeledContent("I/O buffer", value: String(format: "%.1f ms", details.ioBufferDuration * 1000))
            LabeledContent("Input latency", value: String(format: "%.1f ms", details.inputLatency * 1000))
            LabeledContent("Output latency", value: String(format: "%.1f ms", details.outputLatency * 1000))
            LabeledContent("Other audio playing", value: details.isOtherAudioPlaying ? "Yes" : "No")
            LabeledContent("Interrupted", value: audio.isInterrupted ? "Yes (\(audio.lastInterruptionReason ?? ""))" : "No")
            LabeledContent("Current input") { Text(audio.route.inputSummary).multilineTextAlignment(.trailing) }
            LabeledContent("Current output") { Text(audio.route.outputSummary).multilineTextAlignment(.trailing) }
            LabeledContent("Preferred input", value: details.preferredInput ?? "System default")
            LabeledContent("Available inputs") {
                Text(audio.availableInputs.isEmpty ? "None reported" : audio.availableInputs.map(\.summary).joined(separator: "\n"))
                    .multilineTextAlignment(.trailing)
            }
            if let change = audio.lastRouteChange {
                LabeledContent("Last route change", value: "\(change.reason), \(change.at.formatted(date: .omitted, time: .standard))")
            }
            if let error = audio.lastError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            SystemInputPickerButton()
                .frame(height: 44)
                .disabled(!audio.activeDemands.contains(.microphoneSensing))
            HStack {
                Text("Output route")
                Spacer()
                OutputRoutePicker().frame(width: 44, height: 44)
            }
            Button("Speak test prompt") {
                env.alerts.notify(.testPrompt, category: .test)
            }
            Button("Refresh") { audio.refreshRoute() }
        } header: {
            Text("Audio session")
        } footer: {
            Text("Available Bluetooth inputs only appear while a recording category with Bluetooth input is active. The system microphone picker works while the microphone is running.")
        }
    }
}

private struct MicrophoneSection: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let mic = env.microphone
        Section {
            if !env.ride.isRiding {
                Button(env.isMicrophoneTestRunning ? "Stop microphone test" : "Start microphone test") {
                    if env.isMicrophoneTestRunning {
                        env.stopMicrophoneTest()
                    } else {
                        Task { await env.startMicrophoneTest() }
                    }
                }
            }
            LabeledContent("Permission", value: mic.permission.label)
            LabeledContent("Health", value: "\(mic.health.label): \(mic.health.detail)")
            LabeledContent("Format", value: mic.format?.description ?? "—")
            LabeledContent("Buffers received", value: "\(mic.buffersReceived)")
            LabeledContent("Restarts", value: "\(mic.restartCount)")
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                VStack(alignment: .leading, spacing: 6) {
                    if let last = mic.lastBufferAt {
                        Text(String(format: "Last buffer %.1f s ago", context.date.timeIntervalSince(last)))
                            .monospacedDigit()
                    }
                    if let level = mic.level, mic.isRunning {
                        Text(String(format: "Input level %.0f dBFS RMS · peak %.0f dBFS", level.rmsDBFS, level.peakDBFS))
                            .monospacedDigit()
                        ProgressView(value: Double(max(0, min(1, (level.rmsDBFS + 80) / 80))))
                            .accessibilityLabel("Input level")
                    }
                }
                .onAppear { if !env.ride.isRiding { mic.evaluateHealth(now: context.date) } }
                .onChange(of: context.date) { _, date in if !env.ride.isRiding { mic.evaluateHealth(now: date) } }
            }
        } header: {
            Text("Microphone")
        } footer: {
            Text("Input level is loudness only. It is not, and is never used as, vehicle detection.")
        }
    }
}

private struct SamplesSection: View {
    @Environment(AppEnvironment.self) private var env
    @State private var sampleToDelete: AudioSample?

    var body: some View {
        let samples = env.samples
        Section {
            if !env.settings.recordingConsent {
                Text("Sample collection is off. Turn on consent in Settings to record.")
                    .foregroundStyle(.secondary)
            } else if samples.isRecording {
                Button("Stop recording", role: .destructive) { samples.stopRecording() }
            } else {
                Button("Record \(Int(samples.maxDuration)) s sample") { samples.startRecording() }
                    .disabled(!env.microphone.isRunning)
            }
            if let error = samples.lastError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            ForEach(samples.samples) { sample in
                HStack {
                    VStack(alignment: .leading) {
                        Text(sample.recordedAt.formatted(date: .abbreviated, time: .standard))
                        Text(String(format: "%.1f s · %@", sample.duration, sample.inputDescription))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        if env.samplePlayer.playingID == sample.id {
                            env.samplePlayer.stop()
                        } else {
                            env.samplePlayer.play(sample, from: samples)
                        }
                    } label: {
                        Image(systemName: env.samplePlayer.playingID == sample.id ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(env.samplePlayer.playingID == sample.id ? "Stop playback" : "Play sample")
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { sampleToDelete = sample }
                }
            }
        } header: {
            Text("Audio samples (consent required)")
        } footer: {
            Text("Labelling for a dataset arrives in Milestone 2. Swipe a sample to delete it.")
        }
        .confirmationDialog("Delete this sample?", isPresented: Binding(get: { sampleToDelete != nil }, set: { if !$0 { sampleToDelete = nil } }), titleVisibility: .visible) {
            Button("Delete sample", role: .destructive) {
                if let sample = sampleToDelete { samples.delete(sample) }
                sampleToDelete = nil
            }
        } message: {
            Text("The audio file is removed from this iPhone permanently.")
        }
    }
}

private struct AlertLogSection: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Section {
            if env.alerts.log.isEmpty && env.alerts.notices.isEmpty {
                Text("No events this ride.").foregroundStyle(.secondary)
            }
            ForEach(env.alerts.log.prefix(30)) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(entry.event.kind.displayLabel) — \(entry.decision.label)")
                        .font(.subheadline.weight(.semibold))
                    Text("\(entry.event.source.displayName) · observed \(entry.event.sourceTimestamp.formatted(date: .omitted, time: .standard)) · decided \(entry.decidedAt.formatted(date: .omitted, time: .standard))\(entry.spoken ? " · spoken" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(env.alerts.notices.prefix(10)) { notice in
                Text("Notice: \"\(notice.phrase.text)\" · \(notice.at.formatted(date: .omitted, time: .standard))\(notice.spoken ? "" : " · not spoken")")
                    .font(.caption)
            }
        } header: {
            Text("Alert decisions")
        } footer: {
            let policy = env.alerts.policy
            Text("Max event age \(policy.maxEventAge, format: .number) s · de-duplication window \(policy.dedupWindow, format: .number) s · cooldown \(policy.cooldown, format: .number) s.")
        }
    }
}

private struct StoredRidesSection: View {
    @Environment(AppEnvironment.self) private var env
    @State private var confirmDeleteAll = false

    var body: some View {
        Section {
            if env.history.rides.isEmpty {
                Text("No stored rides.").foregroundStyle(.secondary)
            }
            ForEach(env.history.rides) { ride in
                VStack(alignment: .leading, spacing: 2) {
                    Text(ride.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline.weight(.semibold))
                    Text("\(ride.detectorName)\(ride.detectorIsSimulated ? " (simulated)" : "") · \(AgeFormatter.duration(ride.duration ?? 0))")
                        .font(.caption)
                    Text("Announced \(ride.counts.announced) · suppressed \(ride.counts.suppressed) · stale \(ride.counts.rejectedStale) · incidents \(ride.healthIncidents.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { env.history.delete(ids: [ride.id]) }
                }
            }
            if !env.history.rides.isEmpty {
                Button("Delete all rides", role: .destructive) { confirmDeleteAll = true }
            }
            if let error = env.history.lastError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Stored rides")
        } footer: {
            Text("Ride summaries are stored on this iPhone only. They contain no audio and no location.")
        }
        .confirmationDialog("Delete all stored rides?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete all rides", role: .destructive) { env.history.deleteAll() }
        }
    }
}
