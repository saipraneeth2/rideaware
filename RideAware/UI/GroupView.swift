import SwiftUI

struct GroupView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label(env.group.transportStatus.label, systemImage: "wifi.slash")
                        .font(.subheadline)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.yellow.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                    if let group = env.group.group {
                        ActiveGroupContent(group: group)
                    } else {
                        CreateGroupCard()
                        JoinGroupCard()
                    }
                }
                .padding()
            }
            .navigationTitle("Group")
        }
    }
}

private struct CreateGroupCard: View {
    @Environment(AppEnvironment.self) private var env
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        Card(title: "Create a private group", systemImage: "plus.circle.fill") {
            TextField("Group name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .submitLabel(.done)
            Button {
                do {
                    try env.group.createGroup(name: name)
                    error = nil
                } catch let failure {
                    error = failure.localizedDescription
                }
            } label: {
                Text("Create group").font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            Text("You will get an invitation code that expires after \(Int(InviteCode.defaultLifetime / 60)) minutes.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
    }
}

private struct JoinGroupCard: View {
    @Environment(AppEnvironment.self) private var env
    @State private var code = ""
    @State private var error: String?

    var body: some View {
        Card(title: "Join with a code", systemImage: "person.badge.plus") {
            TextField("ABC-234", text: $code)
                .textFieldStyle(.roundedBorder)
                .font(.title2.monospaced())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .accessibilityLabel("Invitation code")
            Button {
                do {
                    try env.group.join(code: code)
                    error = nil
                } catch let failure {
                    error = failure.localizedDescription
                }
            } label: {
                Text("Join group").font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.bordered)
            .disabled(code.isEmpty)
            if let error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
    }
}

private struct ActiveGroupContent: View {
    @Environment(AppEnvironment.self) private var env
    let group: RideGroup
    @State private var confirmLeave = false

    var body: some View {
        Card(title: group.name, systemImage: "person.3.fill") {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    Text("Invitation code").font(.subheadline).foregroundStyle(.secondary)
                    Text(group.invite.formatted)
                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                        .textSelection(.enabled)
                        .accessibilityLabel("Invitation code \(group.invite.value.map(String.init).joined(separator: " "))")
                    if group.invite.isExpired(at: context.date) {
                        Text("Expired. New riders cannot join with this code.").font(.footnote).foregroundStyle(.red)
                    } else {
                        Text("Expires in \(Int(group.invite.expiresAt.timeIntervalSince(context.date) / 60) + 1) min")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }

        Card(title: "Send a message", systemImage: "megaphone.fill") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(GroupReportKind.allCases) { kind in
                    Button {
                        env.group.send(kind)
                    } label: {
                        Label(kind.title, systemImage: kind.systemImage)
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 64)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(kind == .needHelp ? RideAwareColors.stop : .accentColor)
                    .accessibilityHint("Sends \(kind.title) to your group")
                }
            }
            Text("Messages are explicit reports from riders. They are never shown as vehicle detections.")
                .font(.footnote).foregroundStyle(.secondary)
        }

        Card(title: "Riders", systemImage: "person.2.fill") {
            ForEach(env.group.presence) { presence in
                HStack {
                    Image(systemName: presence.state == .connected ? "circle.fill" : "circle.dashed")
                        .foregroundStyle(presence.state == .connected ? .green : .secondary)
                        .accessibilityHidden(true)
                    Text(presence.rider.id == env.group.localRider.id ? "\(presence.rider.displayName) (you)"
                         : presence.rider.isSimulated ? "\(presence.rider.displayName) (simulated)" : presence.rider.displayName)
                    Spacer()
                    Text(presence.state.rawValue.capitalized).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }

        Card(title: "Reports", systemImage: "list.bullet") {
            if env.group.feed.isEmpty {
                Text("No reports yet.").foregroundStyle(.secondary)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(env.group.feed) { report in
                            GroupReportRow(report: report, localRiderID: env.group.localRider.id, now: context.date)
                        }
                    }
                }
            }
        }

        Card(title: "Location sharing", systemImage: "location.fill") {
            Toggle("Share my location with this group during the active ride", isOn: Binding(
                get: { env.locationSharing.optedIn },
                set: { env.locationSharing.setOptedIn($0) }
            ))
            .disabled(!env.locationSharing.transportAvailable)
            if let reason = env.locationSharing.unavailableReason {
                Text(reason).font(.footnote).foregroundStyle(.secondary)
            }
            Text("Off by default. Stops immediately when you end the ride or leave the group.")
                .font(.footnote).foregroundStyle(.secondary)
        }

        Card(title: "Group voice", systemImage: "waveform") {
            Text("Not available. Group voice needs a maintained WebRTC stack or managed service (Milestone 3), and stays a separate mode from microphone sensing until both are verified together on hardware.")
                .font(.subheadline).foregroundStyle(.secondary)
        }

        Card(title: "Simulated riders", systemImage: "theatermasks") {
            Text("For testing attribution only. Simulated riders are labelled everywhere.")
                .font(.footnote).foregroundStyle(.secondary)
            HStack {
                Button("Add simulated rider") { env.group.addSimulatedRider() }
                    .buttonStyle(.bordered)
                Menu("Simulated report") {
                    ForEach(GroupReportKind.allCases) { kind in
                        Button(kind.title) { env.group.sendSimulatedReport(kind) }
                    }
                }
                .buttonStyle(.bordered)
            }
        }

        Button(role: .destructive) {
            confirmLeave = true
        } label: {
            Text("Leave group").font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.bordered)
        .confirmationDialog("Leave \(group.name)?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave group", role: .destructive) { env.group.leave() }
        } message: {
            Text("Location sharing stops immediately and the report history on this iPhone is cleared.")
        }
    }
}
