import SwiftUI

/// Admin (Flagcast staff, by admin email or the admin passcode): every club as a photo card with clubs waiting for
/// approval on top, every tournament, any club's TVs and players' phones (Engineering), activity, and More.
struct AdminHome: View {
    @Environment(AppModel.self) private var model
    @Environment(AdminModel.self) private var admin
    var body: some View {
        List {
            SwiftUI.Section {
                NavigationLink { ClubsView() } label: { row("Clubs", "building.2", admin.clubs.filter { $0.status == "pending" }.count) }
                NavigationLink { AdminTournaments() } label: { row("Tournaments", "flag.2.crossed", 0) }
                NavigationLink { AdminScreens() } label: { row("TVs & phones", "tv.and.mediabox", 0) }
                NavigationLink { AdminActivity() } label: { row("Activity", "list.bullet.rectangle", 0) }
            } header: { Text("Flagcast Admin") }
            SwiftUI.Section { NavigationLink { MoreView() } label: { Label("More: contests, details, links, settings", systemImage: "ellipsis.circle") } }
        }
        .scrollContentBackground(.hidden).background(FC.paper)
        .navigationTitle("Admin")
        .task { try? await admin.refresh() }
        .refreshable { try? await admin.refresh(); await admin.refreshEvents() }
    }
    private func row(_ t: String, _ icon: String, _ badge: Int) -> some View {
        HStack { Label(t, systemImage: icon); Spacer(); if badge > 0 { Text("\(badge) waiting").font(.caption.weight(.bold)).padding(.horizontal, 7).padding(.vertical, 3).background(FC.flag, in: Capsule()).foregroundStyle(FC.onFlag) } }
    }
}

/// Every club as a full-photo card; clubs asking to join on top, with Approve and Decline.
struct ClubsView: View {
    @Environment(AdminModel.self) private var admin
    @State private var search = ""
    @State private var opened: AdminClub?
    @State private var adding = false
    private var shown: [AdminClub] {
        let q = search.lowercased()
        return admin.clubs.filter { q.isEmpty || $0.name.lowercased().contains(q) || $0.city.lowercased().contains(q) }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(admin.clubs.filter { $0.status == "pending" }) { c in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Text("!").font(.system(size: 16, weight: .bold)).foregroundStyle(FC.onFlag).frame(width: 34, height: 34).background(FC.flag, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(c.name) asked to join").font(.subheadline.weight(.bold)).foregroundStyle(Color(hex: 0x14201a))
                                Text(["Signed up \(Date(timeIntervalSince1970: c.created / 1000).formatted(.relative(presentation: .named)))", c.city.isEmpty ? nil : c.city].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(Color(hex: 0x56625a))
                            }
                        }
                        HStack(spacing: 8) {
                            Button("Decline") { Task { await admin.act("off", ["club": c.id], done: "Declined.") } }.buttonStyle(PlainCardButton(full: true))
                            Button("Approve") { Task { await admin.act("approve", ["club": c.id], done: "Approved. They have an email.") } }.buttonStyle(GreenButton(full: true))
                        }
                    }
                    .padding(14).background(Color(hex: 0xfff8e1), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xecd58a)))
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 460), spacing: 14)], spacing: 14) {
                    ForEach(shown) { c in ClubCard(club: c) { opened = c } }
                }
                if shown.isEmpty { Text(admin.clubs.isEmpty ? "No clubs yet" : "No club matches").foregroundStyle(FC.muted).padding(30) }
            }
            .padding(16)
        }
        .background(FC.paper)
        .navigationTitle("Clubs")
        .searchable(text: $search, prompt: "Find a club")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Label("New club", systemImage: "plus") } } }
        .refreshable { try? await admin.refresh() }
        .overlay(alignment: .bottom) { NoticeBar(text: admin.notice).padding(.bottom, 10).animation(.snappy, value: admin.notice) }
        .sheet(item: $opened) { c in NavigationStack { ClubDetail(club: admin.clubs.first { $0.id == c.id } ?? c) } }
        .sheet(isPresented: $adding) { NavigationStack { NewClub() } }
        .task { try? await admin.refresh() }
    }
}

/// One club as a photo card: status, name and town, tournaments left / made / staff, +1, +5, Open.
private struct ClubCard: View {
    @Environment(AdminModel.self) private var admin
    let club: AdminClub
    var open: () -> Void
    @State private var image: UIImage?
    var body: some View {
        ZStack(alignment: .topLeading) {
            CourseHeroImage(image: image)
            LinearGradient(stops: [.init(color: FC.scrim.opacity(0.92), location: 0), .init(color: FC.scrim.opacity(0.35), location: 0.6), .init(color: FC.scrim.opacity(0.1), location: 1)], startPoint: .bottom, endPoint: .top)
            Text(club.statusText.uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.6).padding(.horizontal, 7).padding(.vertical, 3)
                .background(club.status == "active" ? FC.flag : club.status == "pending" ? Color.white : FC.red, in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(club.status == "off" ? .white : FC.onFlag).padding(12)
            VStack(alignment: .leading, spacing: 10) {
                Spacer()
                VStack(alignment: .leading, spacing: 1) {
                    Text(club.name).font(FC.display(30)).lineLimit(1).minimumScaleFactor(0.6)
                    Text(club.city.isEmpty ? "No town on file" : club.city).font(.caption).opacity(0.85)
                }
                HStack(spacing: 14) { stat(club.creditsText, "left"); stat("\(club.events.count)", "tournaments"); stat("\(club.members.count)", "staff") }
                HStack(spacing: 6) {
                    Button("+1") { Task { await admin.act("credits", ["club": club.id, "add": 1]) } }.buttonStyle(WhiteButton()).disabled(club.credits < 0)
                    Button("+5") { Task { await admin.act("credits", ["club": club.id, "add": 5]) } }.buttonStyle(WhiteButton()).disabled(club.credits < 0)
                    Spacer()
                    Button("Open", action: open).buttonStyle(WhiteButton())
                }
            }
            .foregroundStyle(.white).padding(16)
        }
        .frame(height: 250).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle()).onTapGesture(perform: open)
        .task(id: club.id) { image = await CourseImages.place([club.name, club.city].filter { !$0.isEmpty }.joined(separator: " "), key: club.id) }
    }
    private func stat(_ v: String, _ l: String) -> some View { Text(v).font(.system(size: 15, weight: .bold)) + Text(" \(l)").font(.caption) }
}

/// A club: approve / switch on or off, tournaments left, its people and tournaments.
private struct ClubDetail: View {
    @Environment(AdminModel.self) private var admin
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let club: AdminClub
    var body: some View {
        Form {
            SwiftUI.Section {
                LabeledContent("Status", value: club.statusText)
                if club.status == "pending" { Button("Approve") { Task { await admin.act("approve", ["club": club.id], done: "Approved. They have an email.") } } }
                if club.status == "off" { Button("Switch On") { Task { await admin.act("on", ["club": club.id], done: "Switched on.") } } }
                if club.status == "active" { Button("Switch Off", role: .destructive) { Task { await admin.act("off", ["club": club.id], done: "Switched off.") } } }
            }
            SwiftUI.Section("Tournaments left to make") {
                HStack {
                    Text(club.creditsText).font(FC.display(30))
                    Spacer()
                    Button("−1") { Task { await admin.act("credits", ["club": club.id, "add": -1]) } }.disabled(club.credits <= 0)
                    Button("+1") { Task { await admin.act("credits", ["club": club.id, "add": 1]) } }.disabled(club.credits < 0)
                    Button("+5") { Task { await admin.act("credits", ["club": club.id, "add": 5]) } }.disabled(club.credits < 0)
                }
                .buttonStyle(.bordered)
                Button(club.credits < 0 ? "Set a Number" : "Make Unlimited") { Task { await admin.act("credits", ["club": club.id, "set": club.credits < 0 ? 0 : -1]) } }
            }
            SwiftUI.Section("Contact") {
                if !club.contact.isEmpty { LabeledContent("Name", value: club.contact) }
                if !club.phone.isEmpty { LabeledContent("Phone", value: club.phone) }
                if !club.city.isEmpty { LabeledContent("Town", value: club.city) }
            }
            SwiftUI.Section("People") {
                ForEach(club.members, id: \.email) { m in LabeledContent(m.email, value: m.role == "owner" ? "Owner" : "Staff") }
            }
            SwiftUI.Section("Tournaments") {
                ForEach(club.events) { e in
                    Button { model.openAdmin(id: e.id, key: e.key, name: e.name, club: club.name); dismiss() } label: {
                        HStack { Text(e.name); Spacer(); if e.archived { Text("Archived").foregroundStyle(FC.muted) } else if e.hidden { Text("Hidden").foregroundStyle(FC.muted) } }
                    }
                }
            }
        }
        .navigationTitle(club.name).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

private struct NewClub: View {
    @Environment(AdminModel.self) private var admin
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var contact = ""
    @State private var phone = ""
    @State private var city = ""
    @State private var credits = 1
    var body: some View {
        Form {
            SwiftUI.Section("Club") { TextField("Club name", text: $name); TextField("Town", text: $city) }
            SwiftUI.Section { TextField("Owner’s email", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never); TextField("Contact name", text: $contact); TextField("Phone", text: $phone).keyboardType(.phonePad) } header: { Text("Owner") } footer: { Text("They get an email with how to sign in.") }
            SwiftUI.Section { Stepper("\(credits) tournament\(credits == 1 ? "" : "s")", value: $credits, in: 0...100) }
        }
        .navigationTitle("New club").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Set Up") { Task { await admin.act("create", ["name": name, "email": email, "contact": contact, "phone": phone, "city": city, "credits": credits], done: "Club set up."); dismiss() } }.disabled(name.isEmpty)
            }
        }
    }
}

/// Every tournament on every club's list: open it here, lock, archive, hide.
private struct AdminTournaments: View {
    @Environment(AdminModel.self) private var admin
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var showHidden = false
    private var shown: [AdminEvent] {
        let q = search.lowercased()
        return admin.events.filter { (showHidden || (!$0.hidden && !$0.archived)) && (q.isEmpty || $0.name.lowercased().contains(q) || $0.clubName.lowercased().contains(q) || $0.id.contains(q)) }
            .sorted { $0.created > $1.created }
    }
    var body: some View {
        List {
            Toggle("Show hidden and archived", isOn: $showHidden)
            ForEach(shown) { e in
                Button { model.openAdmin(id: e.id, key: e.key, name: e.name, club: e.clubName) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Text(e.name).font(.headline).foregroundStyle(FC.ink); Spacer(); Text(e.gone ? "Gone" : e.archived ? "Archived" : e.locked ? "Final" : e.hidden ? "Hidden" : "Open").font(.caption).foregroundStyle(FC.muted) }
                        Text([e.clubName, e.date, "\(e.teams) teams", e.screens > 0 ? "\(e.online)/\(e.screens) TVs on" : ""].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(FC.muted)
                    }
                }
                .swipeActions {
                    Button(e.locked ? "Unlock" : "Lock") { Task { await admin.act("lock", ["id": e.id, "locked": !e.locked]) } }.tint(FC.blue)
                    Button(e.archived ? "Unarchive" : "Archive") { Task { await admin.act("archive", ["id": e.id, "on": !e.archived]) } }.tint(FC.muted)
                    Button(e.hidden ? "Show" : "Hide") { Task { await admin.act(e.hidden ? "unhide" : "hide", ["id": e.id]) } }
                }
            }
        }
        .scrollContentBackground(.hidden).background(FC.paper)
        .navigationTitle("Tournaments")
        .searchable(text: $search, prompt: "Find a tournament or club")
        .task { await admin.refreshEvents() }
        .refreshable { await admin.refreshEvents() }
    }
}

/// Any club's TVs and players' phones, in Engineering.
private struct AdminScreens: View {
    @Environment(AdminModel.self) private var admin
    @State private var eventId: String?
    private var live: [AdminEvent] { admin.events.filter { !$0.gone && !$0.archived && !$0.hidden }.sorted { ($0.online, $0.created) > ($1.online, $1.created) } }
    private var e: AdminEvent? { admin.events.first { $0.id == eventId } ?? live.first }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Tournament", selection: Binding(get: { e?.id ?? "" }, set: { eventId = $0 })) {
                    ForEach(live) { x in Text("\(x.name) · \(x.clubName)\(x.online > 0 ? " · \(x.online) on" : "")").tag(x.id) }
                }
                .pickerStyle(.menu).card(padding: 8)
                if let e { EngineeringPanel(src: source(e)) } else { Text("No tournaments right now.").foregroundStyle(FC.muted) }
            }
            .padding(16)
        }
        .background(FC.paper)
        .navigationTitle("TVs & phones")
        .overlay(alignment: .bottom) { NoticeBar(text: admin.notice).padding(.bottom, 10).animation(.snappy, value: admin.notice) }
        .task { while !Task.isCancelled { await admin.refreshEvents(); try? await Task.sleep(for: .seconds(15)) } }
    }
    private func source(_ e: AdminEvent) -> EngSource {
        EngSource(
            tvs: e.displays.map { EngTV(id: $0.id, name: $0.name, place: $0.place, group: $0.group, online: $0.online, force: $0.force, playlist: $0.list) },
            choices: PageChoices(flights: e.flights, p3: e.p3, sponsors: e.sponsors.map { ($0.id, $0.name) }),
            url: { id in URL(string: "\(Server.base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/g/\(e.id)/board?screen=\(id)") },
            scenes: e.scenes.map { ($0.id, $0.name) }, currentScene: e.scene, take: e.take, phone: e.phone, announcement: e.flash,
            replays: e.replayList.map { ($0.id, "Hole \($0.hole) · \($0.label.isEmpty ? "Replay" : $0.label)") },
            day: { op, body, done in var b = body; b["op"] = op; await admin.day(e.id, b, done: done) })
    }
}

private struct AdminActivity: View {
    @Environment(AdminModel.self) private var admin
    var body: some View {
        List(admin.log) { l in
            VStack(alignment: .leading, spacing: 2) {
                Text(l.what).font(.subheadline)
                Text([Date(timeIntervalSince1970: l.at / 1000).formatted(date: .abbreviated, time: .shortened), l.who, admin.clubs.first { $0.id == l.club }?.name ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(FC.muted)
            }
        }
        .scrollContentBackground(.hidden).background(FC.paper)
        .navigationTitle("Activity")
        .task { await admin.refreshLog() }
        .refreshable { await admin.refreshLog() }
    }
}
