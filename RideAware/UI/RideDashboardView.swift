import SwiftUI

struct RideDashboardView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var isStarting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if env.settings.simulationModeEnabled {
                        SimulationBanner(text: simulationText)
                    }
                    rideButton
                    if let ride = env.ride.activeRide {
                        RideTimer(startedAt: ride.startedAt)
                    }
                    MonitoringHealthCard()
                    TrafficEventsCard()
                    if env.group.isInGroup {
                        GroupReportsSummaryCard()
                    }
                    Text("RideAware is an awareness aid. It cannot prevent collisions or guarantee that vehicles are noticed. No alert never means the road is clear.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Ride")
        }
    }

    private var simulationText: String {
        env.settings.useRadarSimulator
            ? "Radar simulator selected. Alerts are not real."
            : "Scenario: \(env.settings.simulationScenario.title). Alerts are not real."
    }

    @ViewBuilder private var rideButton: some View {
        if env.ride.isRiding {
            BigActionButton(title: "Stop ride", systemImage: "stop.fill", color: RideAwareColors.stop,
                            accessibilityHint: "Ends the ride and saves it on this iPhone") {
                env.stopRide()
            }
        } else {
            BigActionButton(title: isStarting ? "Starting…" : "Start ride", systemImage: "play.fill",
                            color: RideAwareColors.start,
                            accessibilityHint: "Starts monitoring and spoken alerts") {
                guard !isStarting else { return }
                isStarting = true
                Task {
                    await env.startRide()
                    isStarting = false
                }
            }
            .disabled(isStarting)
        }
    }
}

private struct RideTimer: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(AgeFormatter.duration(context.date.timeIntervalSince(startedAt)))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Ride time \(AgeFormatter.duration(context.date.timeIntervalSince(startedAt)))")
        }
    }
}

/// Monitoring health, shown separately from traffic events.
private struct MonitoringHealthCard: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let snapshot = env.ride.monitoring
        Card(title: "Monitoring health", systemImage: "heart.text.square") {
            StatusRow(
                title: "Vehicle monitoring",
                value: snapshot.headline,
                detail: snapshot.isRiding && !snapshot.isMonitoringActive ? snapshot.inactiveReason : nil,
                systemImage: snapshot.isMonitoringActive ? "checkmark.shield.fill" : "shield.slash",
                severity: snapshot.severity
            )
            if snapshot.isRiding {
                HealthRow(title: "Detector · \(snapshot.detectorName)", health: snapshot.detector)
            } else {
                StatusRow(title: "Detector", value: detectorIdleLabel, detail: detectorIdleDetail,
                          systemImage: "waveform.badge.magnifyingglass")
            }
            if env.settings.microphoneEnabled {
                HealthRow(title: "Microphone", health: env.ride.isRiding ? snapshot.microphone : env.microphone.health)
            } else {
                StatusRow(title: "Microphone", value: "Off", detail: "Turned off in Settings", systemImage: "mic.slash")
            }
            StatusRow(title: "Audio input", value: env.audio.route.inputSummary, systemImage: "mic")
            StatusRow(title: "Audio output", value: env.audio.route.outputSummary,
                      detail: env.audio.route.outputIsPrivate ? nil : "Alerts will play from a non-private output",
                      systemImage: "headphones",
                      severity: env.audio.route.outputIsPrivate ? .ok : .warning)
            if let mismatch = env.audio.inputMismatch {
                Label(mismatch, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var detectorIdleLabel: String {
        switch env.settings.detectorChoice {
        case .experimentalAcoustic: "Acoustic detection unavailable"
        case .simulation(let scenario): "Simulation: \(scenario.title)"
        case .radarSimulator: "Radar simulator"
        }
    }

    private var detectorIdleDetail: String {
        switch env.settings.detectorChoice {
        case .experimentalAcoustic: ExperimentalAcousticProvider.unavailableReason
        case .simulation, .radarSimulator: "Events will be simulated"
        }
    }
}

/// Traffic events from this phone's detector. Never shows "clear" or "safe".
private struct TrafficEventsCard: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Card(title: "Traffic events", systemImage: "car.rear.waves.up") {
            if !env.ride.isRiding {
                Text("Start a ride to receive alerts.")
                    .foregroundStyle(.secondary)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let last = env.alerts.lastAnnounced {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(last.event.kind.displayLabel)
                                .font(.title2.bold())
                            Text("\(last.event.source.displayName) · observed \(AgeFormatter.string(last.event.age(at: context.date)))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    } else {
                        Text("No detections reported this ride.")
                            .font(.title3.weight(.semibold))
                    }
                }
                if !env.ride.monitoring.isMonitoringActive {
                    Label("Vehicle monitoring is not active, so no detection alerts can be produced.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                let counts = env.alerts.counts
                Text("Announced \(counts.announced) · Suppressed \(counts.suppressed) · Rejected stale \(counts.rejectedStale)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text("No detection is not proof that the road is clear.")
                .font(.footnote.weight(.semibold))
        }
    }
}

/// Reports from other riders, visually separate from local detections.
private struct GroupReportsSummaryCard: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Card(title: "From your group", systemImage: "person.3.fill") {
            Text("Reports from riders. Not detected by this iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if env.group.feed.isEmpty {
                Text("No reports yet.").foregroundStyle(.secondary)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(env.group.feed.prefix(3)) { report in
                            GroupReportRow(report: report, localRiderID: env.group.localRider.id, now: context.date)
                        }
                    }
                }
            }
        }
    }
}

struct GroupReportRow: View {
    let report: GroupReport
    let localRiderID: UUID
    let now: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: report.kind.systemImage)
                .foregroundStyle(report.kind == .needHelp || report.kind == .hazard ? .red : .primary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(report.kind.title).font(.body.weight(.semibold))
                Text("From \(report.origin(localRiderID: localRiderID).label) · \(AgeFormatter.string(report.age(at: now)))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
