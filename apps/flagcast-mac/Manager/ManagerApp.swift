import SwiftUI

@main
struct ManagerApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Flagcast Manager", id: "main") {
            RootView()
                .environment(model)
                .environment(model.nav)
                .frame(minWidth: 980, minHeight: 640)
                .task {
                    await model.refresh()
                    #if DEBUG
                    Snapshots.run(model)
                    SelfTest.run(model)
                    #endif
                }
        }
        .defaultSize(width: 1320, height: 880)
        .commands { ManagerCommands(model: model) }

        Settings { SettingsView().environment(model) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) { Updates.shared.start() }
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

struct ManagerCommands: Commands {
    let model: AppModel
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tournament…") { model.selection = nil; model.focusNew = true }.keyboardShortcut("n")
            Button("Add Tournament by Desk Link…") { model.selection = nil; model.focusAdd = true }
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { Task { await model.current?.save() } }.keyboardShortcut("s").disabled(!(model.current?.dirty ?? false))
            Button("Revert to Saved") { model.current?.revert() }.disabled(!(model.current?.dirty ?? false))
        }
        CommandGroup(after: .appSettings) { Button("Check for Updates…") { Updates.shared.check() } }
        CommandMenu("Tournament") {
            ForEach(Array(Section.allCases.enumerated()), id: \.element) { i, s in
                Button(s.title) { model.section = s }.keyboardShortcut(KeyEquivalent(Character(String(i + 1 == 10 ? 0 : i + 1))), modifiers: .command)
                    .disabled(model.selection == nil)
                if s == .report { Divider() }
            }
            Divider()
            Button(model.current?.ev.locked == true ? "Unlock Results" : "Lock Results") {
                if let d = model.current { Task { await d.setLocked(!d.ev.locked) } }
            }.keyboardShortcut("l", modifiers: [.command, .shift]).disabled(model.current == nil)
            Button("Reload from Flagcast") { if let d = model.current { Task { await d.load() } } }.keyboardShortcut("r").disabled(model.current == nil)
            Divider()
            Button("Open Live Leaderboard") { if let d = model.current { NSWorkspace.shared.open(d.liveURL) } }.disabled(model.current == nil)
            Button("All Tournaments") { model.selection = nil }.keyboardShortcut("h", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .help) {
            Button("Flagcast Help") { NSWorkspace.shared.open(URL(string: "https://flagcast.app")!) }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            if let d = model.current {
                DeskView(doc: d).id(d.id)
            } else {
                HomeView()
            }
        }
        .alert("Flagcast", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}

// MARK: - sidebar

struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @State private var confirmRemove: EventRef?

    var body: some View {
        @Bindable var model = model
        List(selection: Binding<String?>(get: { model.selection.map { "\($0)|\(model.section.rawValue)" } ?? "home" },
                                         set: { v in
            guard let v, v != "home" else { model.selection = nil; return }
            let p = v.split(separator: "|").map(String.init)
            if model.selection != p[0] { model.section = .setup }
            model.selection = p[0]
            if p.count > 1, let s = Section(rawValue: p[1]) { model.section = s }
        })) {
            Label(model.me?.club?.name ?? "Home", systemImage: "house").tag("home")
            SwiftUI.Section("Tournaments") {
                if model.events.isEmpty {
                    Text(model.signedIn ? "No tournaments yet. Press ⌘N to make one." : "Sign in to see your club’s tournaments.")
                        .font(.callout).foregroundStyle(.secondary).padding(.vertical, 4)
                }
                ForEach(model.events) { e in
                    let open = model.selection == e.id
                    EventRow(ref: e, open: open).tag("\(e.id)|\(open ? model.section.rawValue : "setup")")
                        .contextMenu {
                            Button("Open Live Leaderboard") { NSWorkspace.shared.open(URL(string: "\(Server.base.absoluteString)/g/\(e.id)")!) }
                            Button("Copy Desk Link") { copy("\(Server.base.absoluteString)/g/\(e.id)/desk#\(e.key)") }
                            Divider()
                            Button(e.fromClub == true ? "Hide from List…" : "Remove from List…", role: .destructive) { confirmRemove = e }
                        }
                    if open {
                        ForEach(Section.allCases) { s in
                            Label(s.title, systemImage: s.icon).tag("\(e.id)|\(s.rawValue)").padding(.leading, 14)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { AccountRow() }
        .toolbar {
            ToolbarItem { Button { model.selection = nil; model.focusNew = true } label: { Label("New Tournament", systemImage: "plus") }.help("New tournament (⌘N)") }
        }
        .confirmationDialog(confirmRemove?.fromClub == true ? "Hide this tournament from your club’s list?" : "Remove this tournament from this Mac?",
                            isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }), presenting: confirmRemove) { e in
            Button(e.fromClub == true ? "Hide" : "Remove", role: .destructive) { Task { await model.remove(e.id) } }
        } message: { e in Text(e.fromClub == true ? "It isn’t deleted. Its scores and pages stay." : "Copy its desk link first if you’ll need it again: right-click → Copy Desk Link.") }
    }
}

struct EventRow: View {
    let ref: EventRef, open: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(ref.name).fontWeight(.semibold).lineLimit(1)
            Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.vertical, 2)
    }
    var sub: String {
        if let d = ref.date, !d.isEmpty, let date = ISO8601DateFormatter.day.date(from: d) { return date.formatted(date: .abbreviated, time: .omitted) }
        return ref.id.uppercased()
    }
}

struct AccountRow: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.fcGreen).frame(width: 24, height: 24)
                .overlay(Text(String(model.me?.email.first ?? "?").uppercased()).font(.caption.bold()).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 0) {
                Text(model.me?.club?.name ?? model.me?.email ?? "Not signed in").font(.callout.weight(.medium)).lineLimit(1)
                Text(model.me?.email ?? "Sign in on the Home page").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            SettingsLink { Image(systemName: "gearshape") }.buttonStyle(.borderless).help("Settings (⌘,)")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
    }
}

