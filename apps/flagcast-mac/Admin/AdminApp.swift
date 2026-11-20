import SwiftUI

@main
struct AdminApp: App {
    @State private var model = AdminModel()
    @State private var nav = DeskNav()
    @NSApplicationDelegateAdaptor(AdminDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Flagcast Admin", id: "main") {
            AdminRoot()
                .environment(model).environment(nav)
                .frame(minWidth: 1040, minHeight: 660)
        }
        .defaultSize(width: 1380, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Club…") { model.section = .clubs; model.newClub = true; model.openDesk = nil }.keyboardShortcut("n").disabled(!model.unlocked)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { if let id = model.openDesk { Task { await model.docs[id]?.save() } } }.keyboardShortcut("s")
                    .disabled(!(model.openDesk.flatMap { model.docs[$0] }?.dirty ?? false))
            }
            CommandGroup(after: .appSettings) { Button("Check for Updates…") { Updates.shared.check() } }
            CommandMenu("Go") {
                ForEach(Array(AdminSection.allCases.enumerated()), id: \.element) { i, s in
                    Button(s.title) { model.section = s; model.openDesk = nil }.keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: [.command, .option])
                }
                Divider()
                ForEach(Array(Section.allCases.enumerated()), id: \.element) { i, s in
                    Button("Tournament: \(s.title)") { nav.section = s }.keyboardShortcut(KeyEquivalent(Character(String(i + 1 == 10 ? 0 : i + 1))), modifiers: .command).disabled(model.openDesk == nil)
                }
                Divider()
                Button("Refresh") { Task { try? await model.refresh(); await model.refreshEvents(); await model.refreshLog() } }.keyboardShortcut("r")
                Button("Lock Admin") { model.lock() }.keyboardShortcut("l", modifiers: [.command, .control]).disabled(!model.unlocked)
            }
        }
        Settings {
            Form {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                Button("Check for Updates Now") { Updates.shared.check() }
                Button("Forget the Admin Passcode on This Mac") { model.lock() }.disabled(!model.unlocked)
            }.formStyle(.grouped).frame(width: 420, height: 180)
        }
    }
}

final class AdminDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) { Updates.shared.start() }
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

struct AdminRoot: View {
    @Environment(AdminModel.self) private var model
    var body: some View {
        if !model.unlocked { UnlockView() }
        else {
            @Bindable var model = model
            NavigationSplitView {
                AdminSidebar().navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
            } detail: {
                Group {
                    if let id = model.openDesk, let e = model.events.first(where: { $0.id == id }) {
                        DeskView(doc: model.doc(e)).id(id)
                    } else {
                        switch model.section {
                        case .clubs: ClubsView()
                        case .tournaments: TournamentsView()
                        case .screens: ScreenControlView()
                        case .activity: ActivityView()
                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    if let n = model.notice {
                        Text(n).font(.callout.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 8).background(.regularMaterial, in: Capsule()).shadow(radius: 4, y: 2).padding(.bottom, 16)
                    }
                }
                .animation(.snappy, value: model.notice)
            }
            .task { try? await model.refresh(); await model.refreshEvents() }
            .alert("Flagcast Admin", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") {} } message: { Text(model.error ?? "") }
        }
    }
}

struct AdminSidebar: View {
    @Environment(AdminModel.self) private var model
    @Environment(DeskNav.self) private var nav
    var body: some View {
        List(selection: Binding<String?>(get: { model.openDesk.map { "desk|\($0)|\(nav.section.rawValue)" } ?? "sec|\(model.section.rawValue)" }, set: { v in
            guard let v else { return }
            let p = v.split(separator: "|").map(String.init)
            if p[0] == "sec", let s = AdminSection(rawValue: p[1]) { model.section = s; model.openDesk = nil }
            if p[0] == "desk" { if model.openDesk != p[1] { nav.section = .setup }; model.openDesk = p[1]; if p.count > 2, let s = Section(rawValue: p[2]) { nav.section = s } }
        })) {
            SwiftUI.Section("Flagcast") {
                ForEach(AdminSection.allCases) { s in
                    Label(s.title, systemImage: s.icon).tag("sec|\(s.rawValue)")
                        .badge(s == .clubs ? model.clubs.filter { $0.status == "pending" }.count : 0)
                }
            }
            if !model.opened.isEmpty {
                SwiftUI.Section("Open tournaments") {
                    ForEach(model.opened, id: \.self) { id in
                        if let e = model.events.first(where: { $0.id == id }) {
                            let open = model.openDesk == id
                            VStack(alignment: .leading, spacing: 1) { Text(e.name).fontWeight(.semibold).lineLimit(1); Text(e.clubName).font(.caption).foregroundStyle(.secondary) }
                                .tag("desk|\(id)|\(open ? nav.section.rawValue : "setup")")
                                .contextMenu { Button("Close") { model.opened.removeAll { $0 == id }; if open { model.openDesk = nil } } }
                            if open { ForEach(Section.allCases) { s in Label(s.title, systemImage: s.icon).tag("desk|\(id)|\(s.rawValue)").padding(.leading, 14) } }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack { Image(systemName: "lock.open").foregroundStyle(.secondary); Text("Admin unlocked on this Mac").font(.caption).foregroundStyle(.secondary); Spacer()
                Button("Lock") { model.lock() }.controlSize(.small) }
                .padding(.horizontal, 12).padding(.vertical, 8).background(.bar)
        }
    }
}

struct UnlockView: View {
    @Environment(AdminModel.self) private var model
    @State private var pass = ""
    @State private var err: String?
    @State private var busy = false
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Flagcast Admin").font(.largeTitle.bold())
            Text("Enter the admin passcode. It’s kept in this Mac’s Keychain.").foregroundStyle(.secondary)
            SecureField("Admin passcode", text: $pass).textFieldStyle(.roundedBorder).frame(width: 280).onSubmit(go)
            Button("Unlock", action: go).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(pass.isEmpty || busy)
            if let err { Text(err).foregroundStyle(.red) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func go() { busy = true; err = nil; Task { defer { busy = false }; do { try await model.unlock(pass); pass = "" } catch { err = error.localizedDescription } } }
}

// MARK: - clubs

struct ClubsView: View {
    @Environment(AdminModel.self) private var model
    @State private var selection: String?
    @State private var search = ""
    @State private var sort = [KeyPathComparator(\AdminClub.name)]
    private var shown: [AdminClub] {
        let q = search.lowercased()
        return model.clubs.filter { q.isEmpty || $0.name.lowercased().contains(q) || $0.city.lowercased().contains(q) || $0.members.contains { $0.email.contains(q) } }.sorted(using: sort)
    }
    var body: some View {
        @Bindable var model = model
        Table(shown, selection: $selection, sortOrder: $sort) {
            TableColumn("Club", value: \.name) { c in Text(c.name).fontWeight(.medium) }.width(min: 160, ideal: 240)
            TableColumn("Status", value: \.status) { c in StatusPill(text: c.statusText, warn: c.status == "off") }.width(80)
            TableColumn("Tournaments left", value: \.credits) { c in Text(c.creditsText).monospacedDigit() }.width(110)
            TableColumn("Made") { c in Text("\(c.events.count)").monospacedDigit() }.width(50)
            TableColumn("People") { c in Text(c.members.map(\.email).joined(separator: ", ")).foregroundStyle(.secondary).lineLimit(1) }.width(min: 160, ideal: 260)
            TableColumn("Town", value: \.city) { c in Text(c.city).foregroundStyle(.secondary) }.width(min: 80, ideal: 120)
            TableColumn("Paid") { c in Text(c.paid > 0 ? c.paid.formatted(.currency(code: "USD").precision(.fractionLength(0))) : "").monospacedDigit() }.width(70)
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Find a club, town or email")
        .inspector(isPresented: .constant(true)) {
            Group {
                if let c = model.clubs.first(where: { $0.id == selection }) { ClubInspector(club: c).id(c.id) }
                else { ContentUnavailableView("Select a club", systemImage: "building.2", description: Text("\(model.clubs.count) clubs · \(model.clubs.filter { $0.status == "pending" }.count) waiting for approval")) }
            }
            .inspectorColumnWidth(min: 360, ideal: 420, max: 560)
        }
        .toolbar { ToolbarItem { Button { model.newClub = true } label: { Label("New Club", systemImage: "plus") }.help("Set up a club (⌘N)") } }
        .sheet(isPresented: $model.newClub) { NewClubSheet() }
        .navigationTitle("Clubs")
    }
}

struct NewClubSheet: View {
    @Environment(AdminModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var f = ClubRequest()
    @State private var email = ""
    @State private var credits = 1
    var body: some View {
        Form {
            TextField("Club name", text: $f.name)
            TextField("Owner’s email", text: $email, prompt: Text("They sign in to Flagcast Manager with it (optional)"))
            TextField("Contact", text: $f.contact); TextField("Phone", text: $f.phone); TextField("Town and state", text: $f.city)
            Picker("Tournaments", selection: $credits) { ForEach([0, 1, 2, 3, 5, 10, 20], id: \.self) { Text("\($0)").tag($0) }; Text("Unlimited").tag(-1) }
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Set Up Club") { Task { await model.act("create", ["name": f.name, "email": email, "contact": f.contact, "phone": f.phone, "city": f.city, "credits": credits], done: email.isEmpty ? "Club set up." : "Club set up. \(email) has an email with how to sign in."); dismiss() } }
                    .keyboardShortcut(.defaultAction).disabled(f.name.isEmpty) }
        }
        .formStyle(.grouped).frame(width: 460).padding(.vertical, 8)
    }
}

struct ClubInspector: View {
    @Environment(AdminModel.self) private var model
    let club: AdminClub
    @State private var edit = ClubRequest()
    @State private var notes = ""
    @State private var invite = ""
    @State private var pay = (amount: "", credits: 1, what: "Tournament", note: "")
    @State private var claim = ""
    @State private var newEvent = ""
    @State private var confirmDelete = false

    var body: some View {
        Form {
            SwiftUI.Section {
                TextField("Name", text: $edit.name); TextField("Contact", text: $edit.contact); TextField("Phone", text: $edit.phone); TextField("Town", text: $edit.city)
                TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...6)
                HStack { Spacer(); Button("Save Changes") { Task { await model.act("edit", ["club": club.id, "name": edit.name, "contact": edit.contact, "phone": edit.phone, "city": edit.city, "notes": notes], done: "Saved.") } }
                    .disabled(edit.name == club.name && edit.contact == club.contact && edit.phone == club.phone && edit.city == club.city && notes == club.notes) }
            } header: { HStack { Text(club.name); StatusPill(text: club.statusText, warn: club.status == "off") } }
            SwiftUI.Section("Status and tournaments") {
                HStack {
                    if club.status == "pending" { Button("Approve") { Task { await model.act("approve", ["club": club.id], done: "Approved. They have an email.") } }.buttonStyle(.borderedProminent) }
                    if club.status == "off" { Button("Switch On") { Task { await model.act("on", ["club": club.id], done: "Switched on.") } } }
                    if club.status == "active" { Button("Switch Off") { Task { await model.act("off", ["club": club.id], done: "Switched off.") } } }
                    Spacer()
                    if club.events.isEmpty { Button("Delete Club…", role: .destructive) { confirmDelete = true } }
                }
                LabeledContent("Tournaments left") {
                    HStack { Text(club.creditsText).monospacedDigit().fontWeight(.semibold)
                        Button("−1") { Task { await model.act("credits", ["club": club.id, "add": -1]) } }.disabled(club.credits <= 0)
                        Button("+1") { Task { await model.act("credits", ["club": club.id, "add": 1]) } }.disabled(club.credits < 0)
                        Button("+5") { Task { await model.act("credits", ["club": club.id, "add": 5]) } }.disabled(club.credits < 0)
                        Button(club.credits < 0 ? "Limit" : "Unlimited") { Task { await model.act("credits", ["club": club.id, "set": club.credits < 0 ? 0 : -1]) } } }
                }
            }
            SwiftUI.Section("Payments") {
                ForEach(club.payments) { p in
                    HStack { Text(Date(timeIntervalSince1970: p.at / 1000).formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                        Text(p.amount.formatted(.currency(code: "USD"))).monospacedDigit(); Text(p.what + (p.credits != 0 ? " · \(p.credits < 0 ? "unlimited" : "+\(p.credits)")" : "")).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(); Button(role: .destructive) { Task { await model.act("unpay", ["id": p.id]) } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless) }
                }
                HStack {
                    TextField("$", text: $pay.amount).frame(width: 70)
                    Picker("", selection: $pay.credits) { ForEach([0, 1, 2, 3, 5, 10], id: \.self) { Text("+\($0)").tag($0) }; Text("Unlimited").tag(-1) }.labelsHidden().frame(width: 100)
                    TextField("For", text: $pay.what)
                    Button("Record") { Task { await model.act("pay", ["club": club.id, "amount": Double(pay.amount) ?? 0, "credits": pay.credits, "what": pay.what, "note": pay.note], done: "Payment recorded."); pay.amount = "" } }.disabled(Double(pay.amount) == nil)
                }
            }
            SwiftUI.Section("People") {
                ForEach(club.members, id: \.email) { m in
                    HStack {
                        VStack(alignment: .leading) { Text(m.email); Text(m.role + (m.seen > 0 ? " · seen \(Date(timeIntervalSince1970: m.seen / 1000).formatted(.relative(presentation: .named)))" : " · not signed in yet")).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Menu { if m.role != "owner" { Button("Make Owner") { Task { await model.act("role", ["club": club.id, "email": m.email, "role": "owner"]) } } }
                            Button("Sign Out Everywhere") { Task { await model.act("signout", ["email": m.email], done: "Signed out.") } }
                            Button("Remove", role: .destructive) { Task { await model.act("uninvite", ["club": club.id, "email": m.email]) } } } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
                    }
                }
                HStack { TextField("Add someone", text: $invite, prompt: Text("name@club.com")); Button("Add") { Task { await model.act("invite", ["club": club.id, "email": invite], done: "Added. They have an email."); invite = "" } }.disabled(!invite.contains("@")) }
                if !model.mail { Text("Email isn’t switched on, so people aren’t emailed. Tell them yourself.").font(.caption).foregroundStyle(.orange) }
            }
            SwiftUI.Section("Tournaments") {
                ForEach(club.events) { e in
                    HStack {
                        VStack(alignment: .leading) { Text(e.name).fontWeight(.medium); Text(e.id.uppercased() + (e.hidden ? " · hidden" : "") + (e.archived ? " · archived" : "")).font(.caption.monospaced()).foregroundStyle(.secondary) }
                        Spacer()
                        Button("Open") { model.open(e.id) }
                        Button(e.hidden ? "Show" : "Hide") { Task { await model.act(e.hidden ? "unhide" : "hide", ["id": e.id]) } }
                    }
                }
                HStack { TextField("New tournament", text: $newEvent); Button("Make") { Task { await model.act("event", ["club": club.id, "name": newEvent], done: "Made (doesn’t use up a tournament)."); newEvent = "" } }.disabled(newEvent.isEmpty) }
                HStack { TextField("Add an old one by desk link", text: $claim); Button("Add") { Task { await model.act("claim", ["club": club.id, "link": claim], done: "Added to the club."); claim = "" } }.disabled(claim.isEmpty) }
            }
        }
        .formStyle(.grouped)
        .onAppear { edit = ClubRequest(name: club.name, contact: club.contact, phone: club.phone, city: club.city); notes = club.notes }
        .confirmationDialog("Delete \(club.name)?", isPresented: $confirmDelete) { Button("Delete Club", role: .destructive) { Task { await model.act("delete", ["club": club.id], done: "Deleted.") } } } message: { Text("For a mistaken or spam request. It has no tournaments.") }
    }
}

// MARK: - tournaments

struct TournamentsView: View {
    @Environment(AdminModel.self) private var model
    @State private var selection: String?
    @State private var search = ""
    @State private var showHidden = false
    @State private var moving: AdminEvent?
    @State private var sort = [KeyPathComparator(\AdminEvent.created, order: .reverse)]
    private var shown: [AdminEvent] {
        let q = search.lowercased()
        return model.events.filter { (showHidden || (!$0.hidden && !$0.archived)) && (q.isEmpty || $0.name.lowercased().contains(q) || $0.clubName.lowercased().contains(q) || $0.id.contains(q)) }.sorted(using: sort)
    }
    var body: some View {
        Table(shown, selection: $selection, sortOrder: $sort) {
            TableColumn("Tournament", value: \.name) { e in VStack(alignment: .leading) { Text(e.name).fontWeight(.medium); Text(e.id.uppercased()).font(.caption.monospaced()).foregroundStyle(.secondary) } }.width(min: 180, ideal: 260)
            TableColumn("Club", value: \.clubName) { e in Text(e.clubName) }.width(min: 120, ideal: 180)
            TableColumn("Date", value: \.date) { e in Text(e.date) }.width(90)
            TableColumn("Teams", value: \.teams) { e in Text("\(e.teams)").monospacedDigit() }.width(50)
            TableColumn("Scores", value: \.scored) { e in Text("\(e.scored)").monospacedDigit() }.width(55)
            TableColumn("Screens on", value: \.online) { e in Text(e.screens == 0 ? "–" : "\(e.online) of \(e.screens)").monospacedDigit().foregroundStyle(e.online > 0 ? .green : .secondary) }.width(80)
            TableColumn("State") { e in Text(e.gone ? "Gone" : e.archived ? "Archived" : e.locked ? "Final" : e.hidden ? "Hidden" : "Open").foregroundStyle(e.locked || e.archived ? .secondary : .primary) }.width(70)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let e = model.events.first(where: { $0.id == id }) { menu(e) }
        } primaryAction: { ids in if let id = ids.first { model.open(id) } }
        .searchable(text: $search, placement: .toolbar, prompt: "Find a tournament or club")
        .toolbar {
            ToolbarItemGroup {
                Toggle("Show Hidden and Archived", isOn: $showHidden)
                Button { Task { await model.refreshEvents() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                if let id = selection { Button { model.open(id) } label: { Label("Open", systemImage: "arrow.up.forward.app") }.help("Open in the desk (double-click)") }
            }
        }
        .sheet(item: $moving) { e in MoveSheet(event: e) }
        .navigationTitle("Tournaments")
        .task { await model.refreshEvents() }
    }
    @ViewBuilder private func menu(_ e: AdminEvent) -> some View {
        Button("Open in the Desk") { model.open(e.id) }
        Button("Open Live Leaderboard") { NSWorkspace.shared.open(URL(string: "\(Server.base.absoluteString)/g/\(e.id)")!) }
        Button("Copy Desk Link") { copy("\(Server.base.absoluteString)/g/\(e.id)/desk#\(e.key)") }
        Divider()
        Button(e.locked ? "Unlock Results" : "Lock Results") { Task { await model.act("lock", ["id": e.id, "locked": !e.locked]) } }
        Button(e.archived ? "Unarchive" : "Archive") { Task { await model.act("archive", ["id": e.id, "on": !e.archived]) } }
        Button(e.hidden ? "Show on the Club’s List" : "Hide from the Club’s List") { Task { await model.act(e.hidden ? "unhide" : "hide", ["id": e.id]) } }
        Button("Move to Another Club…") { moving = e }
    }
}

struct MoveSheet: View {
    @Environment(AdminModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let event: AdminEvent
    @State private var to = ""
    var body: some View {
        Form {
            Text("Move “\(event.name)” from \(event.clubName) to:")
            Picker("Club", selection: $to) { Text("Pick a club").tag(""); ForEach(model.clubs.filter { $0.id != event.club }) { Text($0.name).tag($0.id) } }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Move") { Task { await model.act("move", ["id": event.id, "to": to], done: "Moved."); dismiss() } }.keyboardShortcut(.defaultAction).disabled(to.isEmpty) }
        }.formStyle(.grouped).frame(width: 420)
    }
}

// MARK: - activity

struct ActivityView: View {
    @Environment(AdminModel.self) private var model
    @State private var search = ""
    var body: some View {
        Table(model.log.filter { search.isEmpty || $0.what.localizedCaseInsensitiveContains(search) || $0.who.localizedCaseInsensitiveContains(search) || clubName($0.club).localizedCaseInsensitiveContains(search) }) {
            TableColumn("When") { l in Text(Date(timeIntervalSince1970: l.at / 1000).formatted(date: .abbreviated, time: .shortened)).monospacedDigit() }.width(150)
            TableColumn("Who") { l in Text(l.who) }.width(min: 120, ideal: 200)
            TableColumn("Club") { l in Text(clubName(l.club)).foregroundStyle(.secondary) }.width(min: 100, ideal: 160)
            TableColumn("What") { l in Text(l.what) }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Find in the activity")
        .toolbar { Button { Task { await model.refreshLog() } } label: { Label("Refresh", systemImage: "arrow.clockwise") } }
        .navigationTitle("Activity")
        .task { await model.refreshLog() }
    }
    private func clubName(_ id: String) -> String { model.clubs.first { $0.id == id }?.name ?? "" }
}

struct StatusPill: View {
    var text: String, warn = false
    var body: some View {
        Text(text.uppercased()).font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2)
            .background(warn ? Color.red : Color.fcFlag, in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(warn ? .white : .black)
    }
}
struct ClubRequest { var name = ""; var contact = ""; var phone = ""; var city = "" }
