import SwiftUI

// MARK: - clubs

/// The header bar of the Admin pages (design/Admin.dc.html): title, counts, find, and the page's buttons.
struct AdminHeader<Actions: View>: View {
    var title: String
    var sub: String
    @Binding var search: String
    var prompt: String
    @ViewBuilder var actions: Actions
    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 15, weight: .bold))
            Text(sub).font(.system(size: 13)).foregroundStyle(FC.muted)
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(FC.muted)
                TextField("", text: $search, prompt: Text(prompt)).textFieldStyle(.plain).font(.system(size: 13))
            }
            .padding(.horizontal, 10).frame(width: 220, height: 30)
            .background(FC.card, in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(FC.line))
            actions
        }
        .padding(.horizontal, 20).frame(height: 56)
        .background(Color(light: 0xfbfcf9, dark: 0x131c17))
        .overlay(alignment: .bottom) { Rectangle().fill(FC.line).frame(height: 1) }
        .contentShape(Rectangle()).gesture(WindowDragGesture())
    }
}

/// Clubs: the ones waiting for approval in a yellow banner, then every club as a photo card.
struct ClubsView: View {
    @Environment(AdminModel.self) private var model
    @AppStorage(ClubLook.key) private var look = ClubLook.photo
    @State private var search = ""
    @State private var opened: AdminClub?
    private var shown: [AdminClub] {
        let q = search.lowercased()
        return model.clubs.filter { q.isEmpty || $0.name.lowercased().contains(q) || $0.city.lowercased().contains(q) || $0.members.contains { $0.email.contains(q) } }
    }
    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            AdminHeader(title: "Clubs", sub: "\(model.clubs.count) club\(model.clubs.count == 1 ? "" : "s") · \(model.clubs.filter { $0.status == "pending" }.count) waiting", search: $search, prompt: "Find a club") {
                Picker("Club cards", selection: $look) { ForEach(ClubLook.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(width: 230).help("How the club cards look: the logo on the place photo, or on the club’s colour")
                Button { model.newClub = true } label: { Label("New club", systemImage: "plus") }.buttonStyle(GreenButton()).help("Set up a club")
            }
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(model.clubs.filter { $0.status == "pending" }) { c in
                        HStack(spacing: 16) {
                            Text("!").font(.system(size: 16, weight: .bold)).foregroundStyle(FC.onFlag).frame(width: 36, height: 36).background(FC.flag, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(c.name) asked to join").font(.system(size: 14, weight: .bold)).foregroundStyle(Color(hex: 0x14201a))
                                Text(["Signed up \(Date(timeIntervalSince1970: c.created / 1000).formatted(.relative(presentation: .named)))", c.city.isEmpty ? nil : c.city, c.by.isEmpty ? nil : c.by].compactMap { $0 }.joined(separator: " · "))
                                    .font(.system(size: 13)).foregroundStyle(Color(hex: 0x56625a))
                            }
                            Spacer()
                            Button("Decline") { Task { await model.act("off", ["club": c.id], done: "Declined.") } }.buttonStyle(PlainCardButton())
                            Button("Approve") { Task { await model.act("approve", ["club": c.id], done: "Approved. They have an email.") } }.buttonStyle(GreenButton())
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Color(hex: 0xfff8e1), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xecd58a)))
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 16)], spacing: 16) {
                        ForEach(shown) { c in ClubCard(club: c) { opened = c } }
                    }
                    if shown.isEmpty {
                        VStack(spacing: 8) { Image(systemName: "building.2").font(.system(size: 30)).foregroundStyle(FC.muted); Text(model.clubs.isEmpty ? "No clubs yet" : "No club matches").font(.headline) }
                            .frame(maxWidth: .infinity, minHeight: 220)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 18)
            }
        }
        .background(FC.paper)
        .sheet(isPresented: $model.newClub) { NewClubSheet() }
        .sheet(item: $opened) { c in
            VStack(spacing: 0) {
                HStack { Text(c.name).font(FC.display(30)); Spacer(); Button("Done") { opened = nil }.buttonStyle(GreenButton()).keyboardShortcut(.defaultAction) }.padding(16)
                ClubInspector(club: model.clubs.first { $0.id == c.id } ?? c).id(c.id)
            }
            .frame(width: 560, height: 700).background(FC.card)
        }
    }
}

/// One club as a full-photo card: status, name and town, tournaments left / made / staff, +1, +5, Open club.
struct ClubCard: View {
    @Environment(AdminModel.self) private var model
    let club: AdminClub
    var open: () -> Void
    @State private var image: NSImage?
    @AppStorage(ClubLook.key) private var look = ClubLook.photo
    var body: some View {
        ZStack(alignment: .topLeading) {
            CourseHeroImage(image: image)
            if look == .logo { ClubLogoBackdrop(club: club) }
            LinearGradient(stops: [.init(color: FC.scrim.opacity(0.92), location: 0), .init(color: FC.scrim.opacity(0.35), location: 0.55), .init(color: FC.scrim.opacity(0.1), location: 1)], startPoint: .bottom, endPoint: .top)
            Text(club.statusText.uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.6).padding(.horizontal, 7).padding(.vertical, 3)
                .background(club.status == "active" ? FC.flag : club.status == "pending" ? Color.white : FC.red, in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(club.status == "off" ? .white : FC.onFlag).padding(12)
            VStack(alignment: .leading, spacing: 10) {
                Spacer()
                VStack(alignment: .leading, spacing: 1) {
                    Text(club.name).font(FC.display(28)).lineLimit(1).minimumScaleFactor(0.6)
                    Text(club.city.isEmpty ? "No town on file" : club.city).font(.system(size: 12)).foregroundStyle(Color(hex: 0xdfe8e1))
                }
                HStack(spacing: 16) {
                    stat(club.creditsText, "left"); stat("\(club.events.count)", "tournaments"); stat("\(club.members.count)", "staff")
                }
                HStack(spacing: 6) {
                    Button("+1") { Task { await model.act("credits", ["club": club.id, "add": 1]) } }.buttonStyle(GlassButton()).disabled(club.credits < 0)
                    Button("+5") { Task { await model.act("credits", ["club": club.id, "add": 5]) } }.buttonStyle(GlassButton()).disabled(club.credits < 0)
                    Button("Open club", action: open).buttonStyle(WhiteButton()).frame(maxWidth: .infinity)
                }
            }
            .foregroundStyle(.white).padding(16)
        }
        .overlay(alignment: .topTrailing) { if look == .photo, let u = logoURL(club.logo) { ClubLogoTile(url: u, name: club.name, size: 64).padding(12) } }
        .frame(maxWidth: .infinity).frame(height: 262).clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle()).onTapGesture(count: 2, perform: open)
        .task(id: club.id) {
            image = await CourseImages.place([club.name, club.city].filter { !$0.isEmpty }.joined(separator: " "), key: club.id)
        }
    }
    private func stat(_ v: String, _ l: String) -> some View {
        (Text(v).font(.system(size: 15, weight: .bold)).foregroundStyle(.white) + Text(" \(l)").font(.system(size: 12)).foregroundStyle(Color(hex: 0xcfdbd2)))
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
            SwiftUI.Section("Branding") {
                BrandingEditor(logo: logoURL(club.logo), accent: club.accent,
                               forWhat: "\(club.name)’s logo shows on its TVs, live page and the players’ app instead of the Flagcast logo. The club can change it in its own settings too.",
                               showPowered: true, powered: club.powered) { changes in await model.brand(club.id, changes) }
                    .id(club.id + club.logo + club.accent)
            }
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
            TableColumn("Tournament", value: \.name) { e in VStack(alignment: .leading) { HStack(spacing: 6) { Text(e.name).fontWeight(.medium); if e.demo { DemoChip() } }; Text(e.id.uppercased()).font(.caption.monospaced()).foregroundStyle(.secondary) } }.width(min: 180, ideal: 260)
            TableColumn("Club", value: \.clubName) { e in HStack(spacing: 8) { ClubLogoTile(url: model.logo(club: e.club), name: e.clubName, size: 22); Text(e.clubName) } }.width(min: 120, ideal: 180)
            TableColumn("Date", value: \.date) { e in Text(e.date) }.width(90)
            TableColumn("Teams", value: \.teams) { e in Text("\(e.teams)").monospacedDigit() }.width(50)
            TableColumn("Scores", value: \.scored) { e in Text("\(e.scored)").monospacedDigit() }.width(55)
            TableColumn("Screens on", value: \.online) { e in Text(e.screens == 0 ? "–" : "\(e.online) of \(e.screens)").monospacedDigit().foregroundStyle(e.online > 0 ? .green : .secondary) }.width(80)
            TableColumn("State") { e in Text(e.gone ? "Gone" : e.archived ? "Archived" : e.locked ? "Final" : e.hidden ? "Hidden" : "Open").foregroundStyle(e.locked || e.archived ? .secondary : .primary) }.width(70)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let e = model.events.first(where: { $0.id == id }) { menu(e) }
        } primaryAction: { ids in if let id = ids.first { model.open(id) } }
        .scrollContentBackground(.hidden)
        .background(FC.card).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(FC.line))
        .padding(20)
        .safeAreaInset(edge: .top, spacing: 0) {
            AdminHeader(title: "Tournaments", sub: "\(model.events.count) on every club’s list", search: $search, prompt: "Find a tournament or club") {
                Toggle("Hidden and archived", isOn: $showHidden).toggleStyle(.checkbox)
                Button { Task { await model.refreshEvents() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(PlainCardButton())
                if let id = selection { Button("Open in the desk") { model.open(id) }.buttonStyle(GreenButton()) }
            }
        }
        .background(FC.paper)
        .sheet(item: $moving) { e in MoveSheet(event: e) }
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
        Divider()
        Button(e.demo ? "Stop Demo (Show the Club’s Logo)" : "Mark as Demo (Show the Flagcast Logo)") { Task { await model.act("demo", ["id": e.id, "on": !e.demo], done: e.demo ? "Shows the club’s logo again." : "Marked Demo: it shows the Flagcast logo.") } }
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
        .scrollContentBackground(.hidden)
        .background(FC.card).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(FC.line))
        .padding(20)
        .safeAreaInset(edge: .top, spacing: 0) {
            AdminHeader(title: "Activity", sub: "Everything that happened, newest first", search: $search, prompt: "Find in the activity") {
                Button { Task { await model.refreshLog() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(PlainCardButton())
            }
        }
        .background(FC.paper)
        .task { await model.refreshLog() }
    }
    private func clubName(_ id: String) -> String { model.clubs.first { $0.id == id }?.name ?? "" }
}

