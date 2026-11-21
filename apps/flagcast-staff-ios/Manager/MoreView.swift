import SwiftUI

/// More: contests, the tournament's details, golf pros and marshals, links to share, tournaments and settings.
/// (For Flagcast admins it sits inside the Admin tab.)
struct MoreView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        CardPage(image: model.current?.picture.image, kicker: model.current.map { $0.ev.name.isEmpty ? "Tournament" : $0.ev.name }, title: "More") {
            if model.current != nil {
                CardBox(title: "This tournament") {
                    NavigationLink { ContestsView() } label: { ListRow(icon: "trophy.fill", iconColor: FC.flag.opacity(0.9), title: "Contests", sub: "Closest to the pin, long drive") { Chevron() } }
                    NavigationLink { WithTournament { DetailsView(doc: $0) } } label: { ListRow(icon: "gearshape.fill", title: "Tournament details", sub: "Name, date, holes, flights, ticker") { Chevron() } }
                    NavigationLink { WithTournament { StaffView(doc: $0) } } label: { ListRow(icon: "person.badge.key.fill", iconColor: FC.blue, title: "Golf pros and marshals", sub: "Their PINs for the phone app") { Chevron() } }
                    NavigationLink { WithTournament { LinksView(doc: $0) } } label: { ListRow(icon: "link", iconColor: FC.ok, title: "Links to share", sub: "Leaderboard, board, scorecards", last: true) { Chevron() } }
                }
            }
            CardBox(title: "You") {
                NavigationLink { TournamentPicker() } label: { ListRow(icon: "rectangle.stack.fill", title: "Tournaments", sub: "Switch, make a new one, add by link") { Chevron() } }
                NavigationLink { SettingsView() } label: { ListRow(icon: "person.crop.circle.fill", iconColor: FC.muted, title: "Settings", sub: model.me?.email ?? "Not signed in", last: true) { Chevron() } }
            }
        }
        .buttonStyle(.plain)
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
        CardPage(image: doc.picture.image, kicker: doc.ev.name, title: "Details") {
            CardBox(title: "Tournament") {
                VStack(alignment: .leading, spacing: 10) {
                    BoxField(placeholder: "Name", text: $doc.ev.name)
                    DatePicker("Date", selection: Binding(get: { ISO8601DateFormatter.day.date(from: doc.ev.date) ?? Date() }, set: { doc.ev.date = ISO8601DateFormatter.day.string(from: $0) }), displayedComponents: .date)
                    BoxField(placeholder: "Club", text: $doc.ev.club)
                    HStack { Text("Course").foregroundStyle(FC.muted); Spacer(); Text(doc.ev.course.name.isEmpty ? "Set on the Mac" : doc.ev.course.name) }
                }
                .padding(14)
            }
            CardBox(title: "Format", footer: "The course, tees, format and course map are set in Flagcast Manager on the Mac.") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Holes", selection: $doc.ev.format.nine) { Text("18 holes").tag(""); Text("Front 9").tag("front"); Text("Back 9").tag("back") }.pickerStyle(.segmented)
                    if !doc.ev.format.isStableford {
                        Picker("Leaderboard shows", selection: $doc.ev.format.show) { Text("Net").tag("net"); Text("Gross").tag("gross") }.pickerStyle(.segmented)
                    }
                    BoxField(placeholder: "Flights, with a comma between (A, B)", text: Binding(get: { doc.ev.flights.joined(separator: ", ") },
                                                                    set: { doc.ev.flights = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
                }
                .padding(14)
            }
            CardBox(title: "On the TVs") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Ticker along the bottom", text: $doc.ev.screens.ticker, axis: .vertical).padding(12).background(FC.paper2, in: RoundedRectangle(cornerRadius: 10))
                    Toggle("Show gross skins", isOn: $doc.ev.screens.skins).tint(FC.primary)
                }
                .padding(14)
            }
        }
    }
}

/// Golf pros and marshals: they sign in to the Flagcast phone app with the tournament code and their PIN.
struct StaffView: View {
    @Bindable var doc: DeskDoc
    var body: some View {
        CardPage(image: doc.picture.image, kicker: doc.ev.name, title: "Pros & marshals") {
            CardBox(footer: "A golf pro can fix scores, switch the TVs and nudge a cart. A marshal can only post contest results. PINs are 4 to 8 digits.") {
                if doc.ev.pins.isEmpty { Text("Nobody yet.").foregroundStyle(FC.muted).padding(14) }
                ForEach($doc.ev.pins) { $p in
                    HStack(spacing: 10) {
                        Image(systemName: p.role == "marshal" ? "flag.fill" : "person.badge.key.fill").foregroundStyle(.white)
                            .frame(width: 32, height: 32).background(p.role == "marshal" ? FC.flag.opacity(0.9) : FC.blue, in: RoundedRectangle(cornerRadius: 8))
                        TextField("Name", text: $p.name).font(.system(size: 16, weight: .semibold))
                        TextField("PIN", text: Binding(get: { p.pin }, set: { p.pin = String($0.filter(\.isNumber).prefix(8)) })).keyboardType(.numberPad)
                            .font(.body.monospaced()).multilineTextAlignment(.center).frame(width: 84).padding(8).background(FC.paper2, in: RoundedRectangle(cornerRadius: 8))
                        Button(role: .destructive) { let id = p.id; doc.ev.pins.removeAll { $0.id == id } } label: { Image(systemName: "minus.circle.fill").foregroundStyle(FC.red) }
                    }
                    .padding(.horizontal, 14).frame(minHeight: 58)
                    .overlay(alignment: .bottom) { Rectangle().fill(FC.hairline).frame(height: 1).padding(.leading, 58) }
                }
            }
            HStack(spacing: 8) {
                Button { add("pro") } label: { Label("Golf Pro", systemImage: "plus") }.buttonStyle(PlainCardButton(full: true))
                Button { add("marshal") } label: { Label("Marshal", systemImage: "plus") }.buttonStyle(PlainCardButton(full: true))
            }
        }
    }
    private func add(_ role: String) {
        doc.ev.pins.append(StaffPin(name: role == "pro" ? "Golf pro" : "Marshal \(doc.ev.pins.filter { $0.role == "marshal" }.count + 1)", role: role, pin: String(format: "%04d", Int.random(in: 1000...9999))))
    }
}

/// The links to share: live leaderboard, the board for TVs, the desk, each team's scorecard.
struct LinksView: View {
    let doc: DeskDoc
    var body: some View {
        CardPage(image: doc.picture.image, kicker: doc.ev.name, title: "Links") {
            CardBox(title: "For everyone") {
                link("Live leaderboard", doc.liveURL, "Players and guests, on their phones", "list.number", FC.ok)
                link("The board", doc.boardURL, "For a TV (or set up each TV on Screens)", "tv.fill", FC.green2, last: true)
            }
            CardBox(title: "Organizers only", footer: "Anyone with the desk link can change this tournament.") {
                link("Desk link", doc.deskURL, "Opens this tournament’s desk", "key.fill", FC.red, last: true)
            }
            let teams = doc.ev.teams.filter { !$0.code.isEmpty }
            if !teams.isEmpty {
                CardBox(title: "Team scorecards") {
                    ForEach(Array(teams.enumerated()), id: \.element.id) { i, t in
                        link(t.displayName.isEmpty ? "Team" : t.displayName, doc.cartURL(t.code), "Cart code \(t.code.uppercased())", "square.and.pencil", FC.primary, last: i == teams.count - 1)
                    }
                }
            }
        }
    }
    private func link(_ t: String, _ u: URL, _ sub: String, _ icon: String, _ color: Color, last: Bool = false) -> some View {
        ShareLink(item: u) { ListRow(icon: icon, iconColor: color, title: t, sub: sub, last: last) { Image(systemName: "square.and.arrow.up").foregroundStyle(FC.link) } }
            .buttonStyle(.plain)
    }
}

/// Account, the admin passcode, engineering tools, sign out.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var passcode = false
    var body: some View {
        CardPage(kicker: model.me?.club?.name ?? "Flagcast Manager", title: "Settings", sub: model.me?.email) {
            CardBox(title: "Account") {
                ListRow(icon: "person.crop.circle.fill", iconColor: FC.muted, title: model.me?.email ?? "Not signed in", sub: model.isAdmin ? "Flagcast admin" : model.me?.club?.name)
                if model.signedIn {
                    NavigationLink { PasswordView() } label: { ListRow(icon: "key.fill", title: model.me?.password == true ? "Change password" : "Set a password", sub: "Then sign in with your email and password") { Chevron() } }
                        .buttonStyle(.plain)
                    Button { Task { await model.signOut() } } label: { ListRow(icon: "rectangle.portrait.and.arrow.right", iconColor: FC.red, title: "Sign Out", last: true) }.buttonStyle(.plain)
                } else {
                    NavigationLink { SignInView() } label: { ListRow(icon: "person.badge.plus", title: "Sign in", last: true) { Chevron() } }.buttonStyle(.plain)
                }
            }
            if let c = model.me?.club {
                CardBox(title: "Your club") {
                    NavigationLink { ClubLogoView() } label: {
                        ListRow(icon: "photo.fill", iconColor: FC.green2, title: "Club logo and colour", sub: c.logo.isEmpty ? "Not set yet: golfers see the Flagcast logo" : "Shows on the TVs, live page and players’ app", last: true) { Chevron() }
                    }
                    .buttonStyle(.plain)
                }
            }
            CardBox(title: "Flagcast staff") {
                Button { passcode = true } label: {
                    ListRow(icon: "lock.shield.fill", iconColor: FC.green2, title: "Flagcast admin passcode", sub: !(model.admin.pass ?? "").isEmpty ? "Unlocked on this phone" : "For Flagcast staff without a sign-in", last: true) { Chevron() }
                }
                .buttonStyle(.plain)
            }
            Text("Flagcast Manager \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                .font(.footnote).foregroundStyle(FC.muted).frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $passcode) { NavigationStack { AdminPasscodeView() } }
    }
}

/// The club's logo and colour (Settings → Your club): they show to golfers and on the TVs instead of the Flagcast logo.
struct ClubLogoView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Form {
            if let c = model.me?.club {
                SwiftUI.Section { BrandingEditor(logo: logoURL(c.logo), accent: c.accent) { changes in await model.brand(changes) }.id(c.logo + c.accent) }
            }
        }
        .navigationTitle("Club logo")
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
        CardPage(kicker: model.me?.email, title: model.me?.password == true ? "New password" : "Set a password") {
            VStack(alignment: .leading, spacing: 12) {
                BoxField(placeholder: "New password", text: $pass, secure: true).textContentType(.newPassword)
                BoxField(placeholder: "Type it again", text: $again, secure: true).textContentType(.newPassword)
                Button { save() } label: { if busy { ProgressView().tint(.white) } else { Text("Save Password") } }.buttonStyle(GreenButton(full: true)).disabled(pass.count < 10 || busy)
                Text(msg ?? "At least 10 characters. Your phone can suggest a strong one.").font(.footnote).foregroundStyle(msg == nil ? FC.muted : FC.red)
            }
            .card()
        }
    }
    private func save() {
        guard pass == again else { msg = "The two don’t match."; return }
        busy = true
        Task { do { try await model.setPassword(pass); dismiss() } catch { msg = error.localizedDescription }; busy = false }
    }
}
