import SwiftUI

@main
struct ManagerApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() { FC.registerFonts() }

    var body: some Scene {
        WindowGroup("Flagcast Manager", id: "main") {
            RootView()
                .environment(model)
                .environment(model.nav)
                .environment(model.admin)
                .frame(minWidth: 1100, minHeight: 700)
                .task {
                    await model.refresh()
                    #if DEBUG
                    Snapshots.run(model)
                    SelfTest.run(model)
                    NDISelfTest.run()
                    #endif
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1380, height: 880)
        .commands { ManagerCommands(model: model) }

        Settings { SettingsView().environment(model) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) { Updates.shared.start() }
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
    /// NDI cameras stop when the app quits: say so first.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let n = MainActor.assumeIsolated { Bridges.shared.running.count }
        guard n > 0 else { return .terminateNow }
        let a = NSAlert()
        a.messageText = "Stop \(n) NDI camera\(n == 1 ? "" : "s")?"
        a.informativeText = "The clubhouse TVs and phones stop getting \(n == 1 ? "this camera" : "these cameras") when Flagcast Manager quits."
        a.addButton(withTitle: "Keep Running"); a.addButton(withTitle: "Quit Anyway")
        if a.runModal() == .alertFirstButtonReturn { return .terminateCancel }
        MainActor.assumeIsolated { Bridges.shared.stopAll() }
        return .terminateNow
    }
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
        CommandGroup(after: .toolbar) {
            Button(model.adminMode ? "Back to Manager" : "Flagcast Admin") { model.adminMode.toggle() }
                .keyboardShortcut("a", modifiers: [.command, .option]).disabled(!model.isAdmin)
        }
        CommandMenu("Tournament") {
            ForEach(Section.allCases) { s in
                if let k = s.key { Button(s.title) { model.section = s }.keyboardShortcut(k, modifiers: .command).disabled(model.selection == nil) }
                else { Button(s.title) { model.section = s }.disabled(model.selection == nil) }
                if s == .report { Divider() }
            }
            Divider()
            Button(model.current?.ev.locked == true ? "Unlock Results" : "Lock Results") {
                if let d = model.current { Task { await d.setLocked(!d.ev.locked) } }
            }.keyboardShortcut("l", modifiers: [.command, .shift]).disabled(model.current == nil)
            Button("Reload from Flagcast") { if let d = model.current { Task { await d.load() } } }.keyboardShortcut("r").disabled(model.current == nil)
            Divider()
            Button("Open the Board") { if let d = model.current { NSWorkspace.shared.open(d.boardURL) } }.disabled(model.current == nil)
            Button("Open Live Leaderboard") { if let d = model.current { NSWorkspace.shared.open(d.liveURL) } }.disabled(model.current == nil)
            Button("Home") { model.adminMode = false; model.selection = nil }.keyboardShortcut("h", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .help) {
            Button("Flagcast Help") { NSWorkspace.shared.open(URL(string: "https://flagcast.app")!) }
            Divider()
            SettingsLink { Text("Flagcast Admin Passcode…") }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 0) {
            if model.isAdmin && model.adminMode {
                AdminSidebar().frame(width: 248)
                AdminPage(section: model.adminSection ?? .overview).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ManagerSidebar().frame(width: 248)
                Group {
                    if let d = model.current { DeskView(doc: d).id(d.id) }
                    else if model.signedIn, model.me != nil, model.me?.club == nil, !model.isAdmin, model.events.isEmpty { WelcomeView() }
                    else if model.signedIn, model.me != nil { HomeDashboard() }
                    else { HomeView() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea()
        .background(FC.paper)
        .alert("Flagcast", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}

// MARK: - the green sidebar (design/Sidebar.dc.html)

struct ManagerSidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(DeskNav.self) private var nav
    @State private var confirmRemove: EventRef?

    var body: some View {
        @Bindable var nav = nav
        VStack(alignment: .leading, spacing: 14) {
            Color.clear.frame(height: 26).contentShape(Rectangle()).gesture(WindowDragGesture())   // room for the window buttons
            if model.isAdmin { ModeSwitch() }
            HStack(spacing: 10) {
                FlagcastMark(size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("FLAGCAST").font(FC.display(22)).tracking(0.5)
                    Text("MANAGER").font(.system(size: 11, weight: .semibold)).tracking(1.6).foregroundStyle(FC.onGreenMuted)
                }
            }
            .padding(.horizontal, 6)
            .contentShape(Rectangle()).onTapGesture { model.selection = nil }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(FC.onGreenMuted)
                TextField("", text: $nav.search, prompt: Text("Find a team or player").foregroundStyle(FC.onGreenMuted))
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .onSubmit { if model.selection != nil { nav.section = .teams } }
                    .onChange(of: nav.search) { _, q in if !q.isEmpty, model.selection != nil, nav.section != .scores { nav.section = .teams } }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(FC.onGreen.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TOURNAMENTS").font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(FC.onGreenMuted).padding(.horizontal, 8).padding(.vertical, 4)
                    if model.events.isEmpty {
                        Text(model.signedIn ? "No tournaments yet. Press ⌘N to make one." : "Sign in to see your club’s tournaments.")
                            .font(.system(size: 12)).foregroundStyle(FC.onGreenMuted).padding(.horizontal, 8).padding(.vertical, 4)
                    }
                    ForEach(model.shownEvents) { e in eventRow(e) }
                }
            }
            .scrollIndicators(.never)
            Button { model.selection = nil; model.focusNew = true } label: {
                HStack(spacing: 8) { Image(systemName: "plus").font(.system(size: 13, weight: .bold)); Text("New tournament"); Spacer(); Text("⌘N").font(.system(size: 11)).foregroundStyle(FC.onGreenMuted) }
                    .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 8)
                    .background(FC.onGreen.opacity(0.10), in: RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider().overlay(FC.onGreen.opacity(0.14))
            Button { model.selection = nil } label: {
                HStack(spacing: 10) {
                    Text(initials).font(.system(size: 12, weight: .bold)).frame(width: 28, height: 28).background(FC.green2, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.me?.club?.name ?? (model.signedIn ? model.me?.email ?? "" : "Sign in")).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(clubLine).font(.system(size: 11)).foregroundStyle(FC.onGreenMuted).lineLimit(1)
                    }
                    Spacer()
                    SettingsLink { Image(systemName: "gearshape").foregroundStyle(FC.onGreenMuted) }.buttonStyle(.plain).help("Settings (⌘,)")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).padding(.horizontal, 6)
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 12)
        .foregroundStyle(FC.onGreen)
        .background(FC.green)
        .environment(\.colorScheme, .dark)
        .confirmationDialog(confirmRemove?.fromClub == true ? "Hide this tournament from your club’s list?" : "Remove this tournament from this Mac?",
                            isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }), presenting: confirmRemove) { e in
            Button(e.fromClub == true ? "Hide" : "Remove", role: .destructive) { Task { await model.remove(e.id) } }
        } message: { e in Text(e.fromClub == true ? "It isn’t deleted. Its scores and pages stay." : "Copy its desk link first if you’ll need it again: right-click → Copy Desk Link.") }
    }

    @ViewBuilder private func eventRow(_ e: EventRef) -> some View {
        let open = model.selection == e.id
        Button { if open { model.selection = nil } else { model.selection = e.id; nav.section = .overview } } label: {
            HStack(spacing: 8) {
                Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .heavy)).foregroundStyle(FC.onGreenMuted).frame(width: 10)
                Text(e.name).font(.system(size: 14, weight: open ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 4)
                if isLive(e) { LiveChip() } else if let d = shortDate(e.date) { Text(d).font(.system(size: 12)).foregroundStyle(FC.onGreenMuted) }
            }
            .padding(.horizontal, 8).padding(.vertical, 7).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open Live Leaderboard") { NSWorkspace.shared.open(URL(string: "\(Server.base.absoluteString)/g/\(e.id)")!) }
            Button("Copy Desk Link") { copy("\(Server.base.absoluteString)/g/\(e.id)/desk#\(e.key)") }
            Divider()
            Button(e.fromClub == true ? "Hide from List…" : "Remove from List…", role: .destructive) { confirmRemove = e }
        }
        if open {
            ForEach(Section.allCases) { s in
                let on = nav.section == s
                Button { nav.section = s } label: {
                    HStack(spacing: 10) {
                        Image(systemName: s.icon).font(.system(size: 13)).frame(width: 18).foregroundStyle(on ? FC.green : FC.onGreenMuted)
                        Text(s.title).font(.system(size: 13, weight: on ? .semibold : .medium)).lineLimit(1).minimumScaleFactor(0.85)
                        Spacer()
                        Text(s.keyLabel).font(.system(size: 11)).foregroundStyle(on ? FC.green.opacity(0.7) : FC.onGreenMuted)
                    }
                    .foregroundStyle(on ? FC.green : Color(hex: 0xdfe8e1))
                    .padding(.leading, 26).padding(.trailing, 8).padding(.vertical, 6)
                    .background(on ? FC.onGreen : .clear, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
    private var initials: String {
        let n = model.me?.club?.name ?? model.me?.email ?? "?"
        return String(n.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
    }
    private var clubLine: String {
        guard let c = model.me?.club else { return model.isAdmin ? "Flagcast admin" : model.signedIn ? "Club not set up yet" : "to see your club’s tournaments" }
        return c.credits < 0 ? "Unlimited tournaments" : "\(c.credits) tournament\(c.credits == 1 ? "" : "s") left"
    }
    private func isLive(_ e: EventRef) -> Bool { e.date == ISO8601DateFormatter.day.string(from: Date()) }
    private func shortDate(_ s: String?) -> String? {
        guard let s, let d = ISO8601DateFormatter.day.date(from: s) else { return nil }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// An Admin page in the Manager window (staff only), with its notices.
struct AdminPage: View {
    @Environment(AdminModel.self) private var admin
    let section: AdminSection
    var body: some View {
        Group {
            switch section {
            case .overview: AdminOverview()
            case .today:
                ScrollView { EventDayList().padding(20) }
                    .safeAreaInset(edge: .top, spacing: 0) { AdminHeader(title: "Event day", sub: "Every club’s tournament on today, the ones needing a look first", search: .constant(""), prompt: "") { EmptyView() } }
                    .background(FC.paper)
            case .signups: SignupsView()
            case .clubs: ClubsView()
            case .tournaments: TournamentsView()
            case .cameras: CamerasView()
            case .screens: ScreenControlView()
            case .activity: ActivityView()
            }
        }
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .bottom) {
            if let n = admin.notice {
                Text(n).font(.callout.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 8).background(.regularMaterial, in: Capsule()).shadow(radius: 4, y: 2).padding(.bottom, 16)
            }
        }
        .animation(.snappy, value: admin.notice)
        .task(id: section) { try? await admin.refresh(); await admin.refreshEvents() }
    }
}
