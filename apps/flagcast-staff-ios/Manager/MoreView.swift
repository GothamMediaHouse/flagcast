import SwiftUI

/// More: contests, the tournament's details, golf pros and marshals, links to share, tournaments and settings.
/// (For Flagcast admins it sits inside the Admin tab.)
struct MoreView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            if let d = model.current {
                SwiftUI.Section(d.ev.name.isEmpty ? "This tournament" : d.ev.name) {
                    NavigationLink { ContestsView() } label: { Label("Contests", systemImage: "trophy") }
                    NavigationLink { WithTournament { DetailsView(doc: $0) } } label: { Label("Tournament details", systemImage: "gearshape") }
                    NavigationLink { WithTournament { StaffView(doc: $0) } } label: { Label("Golf pros and marshals", systemImage: "person.badge.key") }
                    NavigationLink { WithTournament { LinksView(doc: $0) } } label: { Label("Links to share", systemImage: "link") }
                }
            }
            SwiftUI.Section {
                NavigationLink { TournamentPicker() } label: { Label("Tournaments", systemImage: "rectangle.stack") }
                NavigationLink { SettingsView() } label: { Label("Settings", systemImage: "person.crop.circle") }
            }
        }
        .scrollContentBackground(.hidden).background(FC.paper)
        .navigationTitle("More")
    }
}

/// Closest to the pin and long drive: each contest, its leader, and adding results (saved at once).
struct ContestsView: View {
    var body: some View { WithTournament { doc in ContestsPage(doc: doc) } }
}
private struct ContestsPage: View {
    @Bindable var doc: DeskDoc
    var body: some View {
        PhotoPage(image: doc.picture.image, kicker: "Closest to the pin and long drive", title: "Contests", height: 200) { EmptyView() } content: {
            if doc.ev.contests.isEmpty { Text("No contests yet.").foregroundStyle(FC.muted).card() }
            ForEach($doc.ev.contests) { $c in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("\(c.isLongDrive ? "LONG DRIVE" : "CLOSEST TO THE PIN") · HOLE \(c.hole)").font(.system(size: 12, weight: .bold)).tracking(1).foregroundStyle(FC.muted)
                        Spacer()
                        Menu {
                            Picker("Contest", selection: $c.kind) { Text("Closest to the pin").tag("ctp"); Text("Long drive").tag("ld") }
                            Picker("Hole", selection: $c.hole) { ForEach(doc.ev.course.holes, id: \.n) { h in Text("Hole \(h.n) · par \(h.par)").tag(h.n) } }
                            Button("Remove Contest", role: .destructive) { let id = c.id; doc.ev.contests.removeAll { $0.id == id } }
                        } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                    }
                    TextField("Sponsor (optional)", text: $c.sponsor).padding(10).background(FC.paper2, in: RoundedRectangle(cornerRadius: 9))
                    Results(doc: doc, contest: c)
                }
                .card()
            }
            HStack(spacing: 8) {
                Button { add("ctp") } label: { Label("Closest to Pin", systemImage: "flag") }.buttonStyle(PlainCardButton(full: true))
                Button { add("ld") } label: { Label("Long Drive", systemImage: "arrow.up.right") }.buttonStyle(PlainCardButton(full: true))
            }
            Help("Closest to the pin in feet (4.5 = 4 ft 6 in), long drive in yards. Save a new contest before entering results.")
        }
    }
    private func add(_ kind: String) {
        let p3 = doc.ev.course.holes.first { $0.par == 3 }?.n ?? 3, p5 = doc.ev.course.holes.first { $0.par == 5 }?.n ?? 2
        doc.ev.contests.append(Contest(id: Ids.make(), kind: kind, hole: kind == "ld" ? p5 : p3))
    }
}
private struct Results: View {
    let doc: DeskDoc, contest: Contest
    @State private var name = ""
    @State private var dist = ""
    private var saved: Contest? { (doc.live?.contests ?? []).first { $0.id == contest.id } }
    var body: some View {
        if let saved {
            let lead = Core.contestLeader(saved)
            ForEach(Array(saved.entries.enumerated()), id: \.offset) { _, e in
                HStack {
                    if e == lead.first { Image(systemName: "crown.fill").foregroundStyle(FC.flag) }
                    Text(e.name).font(.body.weight(e == lead.first ? .semibold : .regular)); Spacer()
                    Text(Core.fmtDist(saved, e.dist)).monospacedDigit().foregroundStyle(FC.muted)
                    Button(role: .destructive) { Task { await doc.day("contest", ["id": saved.id, "entries": saved.entries.filter { $0 != e }.map { ["name": $0.name, "dist": $0.dist] }]) } } label: { Image(systemName: "minus.circle") }
                }
            }
            HStack {
                TextField("Player", text: $name).padding(10).background(FC.paper2, in: RoundedRectangle(cornerRadius: 9))
                TextField(saved.isLongDrive ? "Yards" : "Feet", text: $dist).keyboardType(.decimalPad).frame(width: 70).padding(10).background(FC.paper2, in: RoundedRectangle(cornerRadius: 9))
                Button("Add") {
                    guard let d = Double(dist), !name.isEmpty else { return }
                    let entries = saved.entries.filter { $0.name.lowercased() != name.lowercased() } + [ContestEntry(name: name, dist: d)]
                    Task { if await doc.day("contest", ["id": saved.id, "entries": entries.map { ["name": $0.name, "dist": $0.dist] }], done: "Result posted.") != nil { name = ""; dist = "" } }
                }
                .buttonStyle(GreenButton()).disabled(name.isEmpty || Double(dist) == nil)
            }
        } else { Help("Save first, then enter results.") }
    }
}

/// The tournament's name, date, club, format and flights.
struct DetailsView: View {
    @Bindable var doc: DeskDoc
    var body: some View {
        Form {
            SwiftUI.Section("Tournament") {
                TextField("Name", text: $doc.ev.name)
                DatePicker("Date", selection: Binding(get: { ISO8601DateFormatter.day.date(from: doc.ev.date) ?? Date() }, set: { doc.ev.date = ISO8601DateFormatter.day.string(from: $0) }), displayedComponents: .date)
                TextField("Club", text: $doc.ev.club)
                LabeledContent("Course", value: doc.ev.course.name.isEmpty ? "Set on the Mac" : doc.ev.course.name)
            }
            SwiftUI.Section {
                Picker("Holes", selection: $doc.ev.format.nine) { Text("18 holes").tag(""); Text("Front 9").tag("front"); Text("Back 9").tag("back") }
                if !doc.ev.format.isStableford {
                    Picker("Leaderboard shows", selection: $doc.ev.format.show) { Text("Net").tag("net"); Text("Gross").tag("gross") }
                }
                TextField("Flights (comma between)", text: Binding(get: { doc.ev.flights.joined(separator: ", ") },
                                                                    set: { doc.ev.flights = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
            } header: { Text("Format") } footer: { Text("The course, tees, format and course map are set in Flagcast Manager on the Mac.") }
            SwiftUI.Section("On the TVs") {
                TextField("Ticker along the bottom", text: $doc.ev.screens.ticker, axis: .vertical)
                Toggle("Show gross skins", isOn: $doc.ev.screens.skins)
            }
        }
        .scrollContentBackground(.hidden).background(FC.paper)
        .navigationTitle("Tournament details")
    }
}

/// Golf pros and marshals: they sign in to the Flagcast phone app with the tournament code and their PIN.
struct StaffView: View {
    @Bindable var doc: DeskDoc
    var body: some View {
        Form {
            SwiftUI.Section {
                ForEach($doc.ev.pins) { $p in
                    HStack {
                        Image(systemName: p.role == "marshal" ? "flag" : "person.badge.key").foregroundStyle(FC.muted).frame(width: 22)
                        TextField("Name", text: $p.name)
                        TextField("PIN", text: Binding(get: { p.pin }, set: { p.pin = String($0.filter(\.isNumber).prefix(8)) })).keyboardType(.numberPad).font(.body.monospaced()).frame(width: 80)
                    }
                    .swipeActions { Button("Remove", role: .destructive) { let id = p.id; doc.ev.pins.removeAll { $0.id == id } } }
                }
                Button { add("pro") } label: { Label("Add a Golf Pro", systemImage: "plus") }
                Button { add("marshal") } label: { Label("Add a Marshal", systemImage: "plus") }
            } footer: { Text("A golf pro can fix scores, switch the TVs and nudge a cart. A marshal can only post contest results. PINs are 4 to 8 digits.") }
        }
        .scrollContentBackground(.hidden).background(FC.paper)
        .navigationTitle("Pros and marshals")
    }
    private func add(_ role: String) {
        doc.ev.pins.append(StaffPin(name: role == "pro" ? "Golf pro" : "Marshal \(doc.ev.pins.filter { $0.role == "marshal" }.count + 1)", role: role, pin: String(format: "%04d", Int.random(in: 1000...9999))))
    }
}

/// The links to share: live leaderboard, the board for TVs, the desk, each team's scorecard.
struct LinksView: View {
    let doc: DeskDoc
    var body: some View {
        List {
            SwiftUI.Section("For everyone") {
                link("Live leaderboard", doc.liveURL, "Players and guests on their phones")
                link("The board", doc.boardURL, "Open on a TV (or set up each TV on the Screens tab)")
            }
            SwiftUI.Section { link("Desk link", doc.deskURL, "Anyone with it can change this tournament") } header: { Text("Organizers only") }
            SwiftUI.Section("Team scorecards") {
                ForEach(doc.ev.teams.filter { !$0.code.isEmpty }) { t in link(t.displayName.isEmpty ? "Team" : t.displayName, doc.cartURL(t.code), "Cart code \(t.code.uppercased())") }
            }
        }
        .scrollContentBackground(.hidden).background(FC.paper)
        .navigationTitle("Links")
    }
    private func link(_ t: String, _ u: URL, _ sub: String) -> some View {
        ShareLink(item: u) {
            VStack(alignment: .leading, spacing: 2) { Text(t).foregroundStyle(FC.ink); Text(sub).font(.caption).foregroundStyle(FC.muted) }
        }
    }
}

/// Account, the admin passcode, engineering tools, sign out.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var passcode = false
    var body: some View {
        Form {
            SwiftUI.Section("Account") {
                LabeledContent("Signed in as", value: model.me?.email ?? "Not signed in")
                if let c = model.me?.club { LabeledContent("Club", value: c.name) }
                if model.signedIn { NavigationLink(model.me?.password == true ? "Change password" : "Set a password") { PasswordView() } }
                if model.signedIn { Button("Sign Out", role: .destructive) { Task { await model.signOut() } } }
                else { NavigationLink("Sign in with your club email") { SignInView() } }
            }
            SwiftUI.Section {
                Button(!(model.admin.pass ?? "").isEmpty ? "Admin passcode: unlocked" : "Flagcast admin passcode…") { passcode = true }
            } footer: { Text("Flagcast staff: the passcode adds the Admin tab without an email sign-in.") }
            SwiftUI.Section {
                Toggle("Show engineering tools", isOn: Binding(get: { model.showEngineering }, set: { model.showEngineering = $0 }))
            } footer: { Text(model.isAdmin ? "You’re a Flagcast admin, so Engineering is always on." : "Adds Engineering to the Screens tab: every TV in one grid, switching several at once, take-overs. Club staff don’t need it.") }
            SwiftUI.Section { LabeledContent("Version", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))") }
        }
        .scrollContentBackground(.hidden).background(FC.paper)
        .navigationTitle("Settings")
        .sheet(isPresented: $passcode) { NavigationStack { AdminPasscodeView() } }
    }
}

/// Set or change the password: then sign in with email + password on any phone, iPad or Mac.
struct PasswordView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var pass = ""
    @State private var again = ""
    @State private var msg: String?
    @State private var busy = false
    var body: some View {
        Form {
            SwiftUI.Section {
                SecureField("New password", text: $pass).textContentType(.newPassword)
                SecureField("Type it again", text: $again).textContentType(.newPassword)
            } footer: { Text(msg ?? "At least 10 characters. Your phone can suggest a strong one.") }
            Button { save() } label: { if busy { ProgressView() } else { Text("Save Password") } }.disabled(pass.count < 10 || busy)
        }
        .navigationTitle(model.me?.password == true ? "Change password" : "Set a password")
    }
    private func save() {
        guard pass == again else { msg = "The two don’t match."; return }
        busy = true
        Task { do { try await model.setPassword(pass); dismiss() } catch { msg = error.localizedDescription }; busy = false }
    }
}
