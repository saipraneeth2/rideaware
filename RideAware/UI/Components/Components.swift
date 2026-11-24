import SwiftUI

extension StreamHealth.Severity {
    var color: Color {
        switch self {
        case .ok: Color(red: 0.0, green: 0.55, blue: 0.25)
        case .info: .secondary
        case .warning: .orange
        case .critical: .red
        }
    }
}

enum RideAwareColors {
    /// Dark enough for white text at large sizes (contrast > 4.5:1).
    static let start = Color(red: 0.0, green: 0.42, blue: 0.2)
    static let stop = Color(red: 0.72, green: 0.08, blue: 0.08)
    static let simulation = Color(red: 0.78, green: 0.36, blue: 0.0)
}

/// Rounded card container used across screens.
struct Card<Content: View>: View {
    let title: String
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// One labelled status line. Status is conveyed by text and icon, not by color alone.
struct StatusRow: View {
    let title: String
    let value: String
    var detail: String?
    var systemImage: String
    var severity: StreamHealth.Severity = .info

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(severity.color)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Text(value).font(.body.weight(.semibold))
                if let detail, !detail.isEmpty {
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value). \(detail ?? "")")
    }
}

struct HealthRow: View {
    let title: String
    let health: StreamHealth

    var body: some View {
        StatusRow(title: title, value: health.label, detail: health.detail,
                  systemImage: health.systemImage, severity: health.severity)
    }
}

/// Persistent banner shown whenever simulated sources are selected.
struct SimulationBanner: View {
    let text: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("SIMULATION MODE").font(.headline)
                Text(text).font(.subheadline)
            }
        } icon: {
            Image(systemName: "theatermasks.fill")
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RideAwareColors.simulation, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Simulation mode. \(text)")
    }
}

/// Visible whenever raw audio is being written to disk.
struct RecordingIndicator: View {
    let startedAt: Date
    let maxDuration: TimeInterval
    let onStop: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "record.circle.fill").symbolEffect(.pulse)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = Int(context.date.timeIntervalSince(startedAt))
                Text("Recording audio sample · \(elapsed) / \(Int(maxDuration)) s")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            Spacer()
            Button("Stop", action: onStop)
                .buttonStyle(.bordered)
                .tint(.white)
                .accessibilityLabel("Stop recording sample")
        }
        .foregroundStyle(.white)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.red)
        .accessibilityElement(children: .contain)
    }
}

enum AgeFormatter {
    static func string(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s < 60 { return "\(s) s ago" }
        if s < 3600 { return "\(s / 60) min ago" }
        return "\(s / 3600) h ago"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
    }
}

/// Large primary control for use while riding.
struct BigActionButton: View {
    let title: String
    let systemImage: String
    let color: Color
    var accessibilityHint: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.title.bold())
                .frame(maxWidth: .infinity, minHeight: 88)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .foregroundStyle(.white)
        .buttonBorderShape(.roundedRectangle(radius: 20))
        .accessibilityHint(accessibilityHint)
    }
}
