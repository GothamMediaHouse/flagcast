import SwiftUI
import UserNotifications

/// Player settings (the gear on the home screen): text size, notifications, the carts and tournaments this phone
/// remembers, and about / privacy / terms.
enum TextSize: String, CaseIterable, Identifiable {
    case standard, large, larger
    var id: String { rawValue }
    var label: String { ["standard": "Standard", "large": "Large", "larger": "Larger"][rawValue]! }
    var dynamic: DynamicTypeSize? { self == .standard ? nil : self == .large ? .xLarge : .xxxLarge }
}

struct PlayerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("flagcast.textSize") private var textSize = TextSize.standard.rawValue
    @State private var notif: UNAuthorizationStatus = .notDetermined
    @State private var recents: [Recent] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Text size", selection: $textSize) { ForEach(TextSize.allCases) { Text($0.label).tag($0.rawValue) } }
                        .pickerStyle(.segmented)
                } header: { Text("Text size") } footer: { Text("Makes the scorecard and leaderboard easier to read in the sun. Your iPhone’s own text size works too.") }

                Section {
                    HStack {
                        Label("Messages from the tournament desk", systemImage: "bell.fill")
                        Spacer()
                        Text(notifText).foregroundStyle(.secondary)
                    }
                    if notif == .notDetermined {
                        Button("Turn On") { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in Task { await load() } } }
                    } else {
                        Button("Change in iPhone Settings") { if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) } }
                    }
                } header: { Text("Notifications") } footer: { Text("The desk can send your cart a note, like “Head to hole 10 for the shotgun start”.") }

                Section {
                    if recents.isEmpty { Text("None yet. Scan your cart card on the home screen.").foregroundStyle(.secondary) }
                    ForEach(recents) { r in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name).fontWeight(.semibold)
                            Text(r.code.isEmpty ? "Watching · \(r.id.uppercased())" : "Cart \(r.code) · \(r.id.uppercased())").font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { idx in for i in idx { Recents.forget(recents[i].id) }; recents = Recents.all() }
                } header: { Text("Your carts and tournaments") } footer: { Text(recents.isEmpty ? "" : "Swipe left to forget one on this phone. Your scores stay with the tournament.") }

                Section("About") {
                    LabeledContent("Version", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                    Link("Privacy", destination: Server.production.appendingPathComponent("privacy/"))
                    Link("Terms", destination: Server.production.appendingPathComponent("terms/"))
                    Link("Contact Flagcast", destination: URL(string: "mailto:hello@flagcast.app")!)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
        }
    }
    private var notifText: String {
        switch notif { case .authorized, .provisional, .ephemeral: "On"; case .denied: "Off"; default: "Not set" }
    }
    private func load() async {
        notif = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        recents = Recents.all()
    }
}
