import SwiftUI

/// Admin (Flagcast staff, by admin email or the admin passcode): every club as a photo card with clubs waiting for
/// approval on top, every tournament, any club's TVs and players' phones (Engineering), activity, and More.
struct AdminHome: View {
    @Environment(AppModel.self) private var model
    @Environment(AdminModel.self) private var admin
    var body: some View {
        let waiting = admin.clubs.filter { $0.status == "pending" }.count
        CardPage(kicker: "Flagcast", title: "Admin", sub: "\(admin.clubs.count) clubs · \(admin.events.filter { !$0.hidden && !$0.archived }.count) tournaments") {
            CardBox {
                NavigationLink { ClubsView() } label: {
                    ListRow(icon: "building.2.fill", title: "Clubs", sub: "Approve, tournaments left, people") {
                        if waiting > 0 { Text("\(waiting) waiting").font(.caption.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 4).background(FC.flag, in: Capsule()).foregroundStyle(FC.onFlag) }
                        Chevron()
                    }
                }
                NavigationLink { AdminTournaments() } label: { ListRow(icon: "flag.2.crossed.fill", iconColor: FC.ok, title: "Tournaments", sub: "Every club’s, open one here") { Chevron() } }
                NavigationLink { AdminCameras() } label: { ListRow(icon: "video.fill", iconColor: FC.red, title: "Cameras", sub: "Par 3 camera links for every tournament") { Chevron() } }
                NavigationLink { AdminScreens() } label: { ListRow(icon: "tv.and.mediabox.fill", iconColor: FC.blue, title: "TVs & phones", sub: "Any club’s TVs, take-overs, phones banner") { Chevron() } }
                NavigationLink { AdminActivity() } label: { ListRow(icon: "list.bullet.rectangle.fill", iconColor: FC.muted, title: "Activity", sub: "Everything that happened", last: true) { Chevron() } }
            }
            CardBox {
                NavigationLink { MoreView() } label: { ListRow(icon: "ellipsis.circle.fill", iconColor: FC.green2, title: "More", sub: "Contests, details, links, tournaments, settings", last: true) { Chevron() } }
            }
        }
        .buttonStyle(.plain)
        .task { try? await admin.refresh(); await admin.refreshEvents() }
        .refreshable { try? await admin.refresh(); await admin.refreshEvents() }
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
        .navigationTitle("Clubs").toolbarBackground(FC.paper, for: .navigationBar)
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
    @State private var image: UIImage?
    var body: some View {
        CardPage(image: image, kicker: club.statusText, title: club.name, sub: club.city.isEmpty ? nil : club.city) {
            HStack(spacing: 8) {
                if club.status == "pending" { Button("Approve") { Task { await admin.act("approve", ["club": club.id], done: "Approved. They have an email.") } }.buttonStyle(GreenButton(full: true)) }
                if club.status == "off" { Button("Switch On") { Task { await admin.act("on", ["club": club.id], done: "Switched on.") } }.buttonStyle(GreenButton(full: true)) }
                if club.status == "active" { Button("Switch Off", role: .destructive) { Task { await admin.act("off", ["club": club.id], done: "Switched off.") } }.buttonStyle(PlainCardButton(full: true)) }
            }
            CardBox(title: "Tournaments left to make") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(club.creditsText).font(FC.display(40))
                        Spacer()
                        Button("−1") { Task { await admin.act("credits", ["club": club.id, "add": -1]) } }.buttonStyle(PlainCardButton()).disabled(club.credits <= 0)
                        Button("+1") { Task { await admin.act("credits", ["club": club.id, "add": 1]) } }.buttonStyle(PlainCardButton()).disabled(club.credits < 0)
                        Button("+5") { Task { await admin.act("credits", ["club": club.id, "add": 5]) } }.buttonStyle(PlainCardButton()).disabled(club.credits < 0)
                    }
                    Button(club.credits < 0 ? "Set a Number Instead" : "Make Unlimited") { Task { await admin.act("credits", ["club": club.id, "set": club.credits < 0 ? 0 : -1]) } }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(FC.link)
                }
                .padding(14)
            }
            let contact = [("person.fill", club.contact), ("phone.fill", club.phone), ("mappin.and.ellipse", club.city)].filter { !$0.1.isEmpty }
            if !contact.isEmpty {
                CardBox(title: "Contact") {
                    ForEach(Array(contact.enumerated()), id: \.offset) { i, c in ListRow(icon: c.0, iconColor: FC.muted, title: c.1, last: i == contact.count - 1) }
                }
            }
            CardBox(title: "People") {
                if club.members.isEmpty { Text("Nobody yet.").foregroundStyle(FC.muted).padding(14) }
                ForEach(Array(club.members.enumerated()), id: \.element.email) { i, m in
                    ListRow(icon: m.role == "owner" ? "crown.fill" : "person.fill", iconColor: m.role == "owner" ? FC.flag.opacity(0.9) : FC.muted, title: m.email, sub: m.role == "owner" ? "Owner" : "Staff", last: i == club.members.count - 1)
                }
            }
            CardBox(title: "Tournaments") {
                if club.events.isEmpty { Text("None yet.").foregroundStyle(FC.muted).padding(14) }
                ForEach(Array(club.events.enumerated()), id: \.element.id) { i, e in
                    Button { model.openAdmin(id: e.id, key: e.key, name: e.name, club: club.name); dismiss() } label: {
                        ListRow(icon: "flag.fill", iconColor: e.archived || e.hidden ? FC.muted : FC.primary, title: e.name, sub: e.archived ? "Archived" : e.hidden ? "Hidden" : "Open it", last: i == club.events.count - 1) { Chevron() }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .overlay(alignment: .bottom) { NoticeBar(text: admin.notice).padding(.bottom, 10).animation(.snappy, value: admin.notice) }
        .task(id: club.id) { image = await CourseImages.place([club.name, club.city].filter { !$0.isEmpty }.joined(separator: " "), key: club.id) }
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
        CardPage(kicker: "Admin", title: "New club") {
            CardBox(title: "Club") { VStack(spacing: 10) { BoxField(placeholder: "Club name", text: $name); BoxField(placeholder: "Town and state", text: $city) }.padding(14) }
            CardBox(title: "Owner", footer: "They get an email with how to sign in.") {
                VStack(spacing: 10) {
                    BoxField(placeholder: "Owner’s email", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    BoxField(placeholder: "Contact name", text: $contact)
                    BoxField(placeholder: "Phone", text: $phone).keyboardType(.phonePad)
                }
                .padding(14)
            }
            CardBox(title: "Tournaments they can make") { Stepper("\(credits) tournament\(credits == 1 ? "" : "s")", value: $credits, in: 0...100).padding(14) }
            Button("Set Up the Club") { Task { await admin.act("create", ["name": name, "email": email, "contact": contact, "phone": phone, "city": city, "credits": credits], done: "Club set up."); dismiss() } }
                .buttonStyle(GreenButton(full: true)).disabled(name.isEmpty)
        }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
}

/// Every tournament on every club's list: open it here; lock, archive, hide from its menu.
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
        CardPage(kicker: "Admin", title: "Tournaments", sub: "\(shown.count) shown") {
            BoxField(placeholder: "Find a tournament or club", text: $search)
            Toggle("Show hidden and archived", isOn: $showHidden).tint(FC.primary).padding(.horizontal, 4)
            CardBox {
                if shown.isEmpty { Text("No tournaments match.").foregroundStyle(FC.muted).padding(14) }
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, e in
                    Button { model.openAdmin(id: e.id, key: e.key, name: e.name, club: e.clubName) } label: {
                        ListRow(icon: "flag.fill", iconColor: e.locked || e.archived ? FC.muted : (e.online > 0 ? FC.ok : FC.primary), title: e.name,
                                sub: [e.clubName, e.date, "\(e.teams) teams", e.screens > 0 ? "\(e.online)/\(e.screens) TVs on" : "", e.gone ? "Gone" : e.archived ? "Archived" : e.locked ? "Final" : e.hidden ? "Hidden" : ""].filter { !$0.isEmpty }.joined(separator: " · "),
                                last: i == shown.count - 1) {
                            Menu {
                                Button(e.locked ? "Unlock Results" : "Lock Results") { Task { await admin.act("lock", ["id": e.id, "locked": !e.locked]) } }
                                Button(e.archived ? "Unarchive" : "Archive") { Task { await admin.act("archive", ["id": e.id, "on": !e.archived]) } }
                                Button(e.hidden ? "Show on the Club’s List" : "Hide from the Club’s List") { Task { await admin.act(e.hidden ? "unhide" : "hide", ["id": e.id]) } }
                            } label: { Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(FC.link) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .overlay(alignment: .bottom) { NoticeBar(text: admin.notice).padding(.bottom, 10).animation(.snappy, value: admin.notice) }
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
        CardPage(kicker: "Admin", title: "Activity", sub: "Newest first") {
            CardBox {
                if admin.log.isEmpty { Text("Nothing yet.").foregroundStyle(FC.muted).padding(14) }
                ForEach(Array(admin.log.prefix(200).enumerated()), id: \.element.id) { i, l in
                    ListRow(title: l.what, sub: [Date(timeIntervalSince1970: l.at / 1000).formatted(date: .abbreviated, time: .shortened), l.who, admin.clubs.first { $0.id == l.club }?.name ?? ""].filter { !$0.isEmpty }.joined(separator: " · "),
                            last: i == min(admin.log.count, 200) - 1)
                }
            }
        }
        .task { await admin.refreshLog() }
        .refreshable { await admin.refreshLog() }
    }
}

/// Every open tournament's par 3s with a camera link per hole. Only Flagcast sets these; clubs pick "Par 3 camera"
/// for a TV and see the status.
private struct AdminCameras: View {
    @Environment(AdminModel.self) private var admin
    @State private var search = ""
    private var shown: [AdminEvent] {
        let q = search.lowercased()
        return admin.events.filter { !$0.gone && !$0.archived && !$0.hidden && !$0.p3.isEmpty && (q.isEmpty || $0.name.lowercased().contains(q) || $0.clubName.lowercased().contains(q)) }
            .sorted { ($0.isToday ? 0 : 1, $1.created) < ($1.isToday ? 0 : 1, $0.created) }
    }
    var body: some View {
        CardPage(kicker: "Admin", title: "Cameras", sub: "Par 3 camera links") {
            BoxField(placeholder: "Find a tournament or club", text: $search)
            Help("Paste each par 3’s https link: an HLS stream (.m3u8) or a web player link (VDO.Ninja view link). Replays need an HLS link that keeps a recording window (DVR). Clubs see “Cameras are set up by Flagcast”.")
            if shown.isEmpty { Text(admin.events.isEmpty ? "Loading tournaments…" : "No open tournaments with par 3s.").foregroundStyle(FC.muted).card() }
            ForEach(shown) { e in CamCard(event: e).id(e.id + e.cams.description) }
        }
        .overlay(alignment: .bottom) { NoticeBar(text: admin.notice).padding(.bottom, 10).animation(.snappy, value: admin.notice) }
        .task { await admin.refreshEvents() }
        .refreshable { await admin.refreshEvents() }
    }
}

private struct CamCard: View {
    @Environment(AdminModel.self) private var admin
    let event: AdminEvent
    @State private var links: [Int: String] = [:]
    @State private var signal: [Int: Bool] = [:]
    @State private var saving = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if event.isToday && !event.locked { LiveChip() }
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.name).font(FC.display(24)).lineLimit(1)
                    Text([event.clubName, event.date].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(FC.muted)
                }
            }
            ForEach(event.p3, id: \.self) { h in
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text("Hole \(h)").font(.subheadline.weight(.semibold)); Spacer(); status(h) }
                    TextField("https://…", text: Binding(get: { links[h] ?? "" }, set: { links[h] = $0 })).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .padding(10).background(FC.paper2, in: RoundedRectangle(cornerRadius: 9))
                }
            }
            Button { Task { saving = true; if await admin.saveCams(event.id, links) { await check() }; saving = false } } label: { if saving { ProgressView().tint(.white) } else { Text("Save Cameras") } }
                .buttonStyle(GreenButton(full: true)).disabled(saving || links.filter { !$0.value.isEmpty } == event.cams)
        }
        .card()
        .task(id: event.id) { links = event.cams; await check() }
    }
    @ViewBuilder private func status(_ h: Int) -> some View {
        let u = event.cams[h] ?? ""
        if u.isEmpty { Text("No camera").font(.caption).foregroundStyle(FC.muted) }
        else if !u.lowercased().contains(".m3u8") { Text("Web player").font(.caption).foregroundStyle(FC.muted) }
        else if let ok = signal[h] { Label(ok ? "Live" : "No signal", systemImage: "circle.fill").font(.caption.weight(.semibold)).foregroundStyle(ok ? FC.ok : FC.red) }
        else { ProgressView().controlSize(.small) }
    }
    private func check() async {
        for (h, u) in event.cams where u.lowercased().contains(".m3u8") {
            guard let url = URL(string: u) else { continue }
            var req = URLRequest(url: url); req.timeoutInterval = 6
            let ok = await ((try? URLSession.shared.data(for: req)).map { d, r in (r as? HTTPURLResponse)?.statusCode == 200 && String(decoding: d.prefix(64), as: UTF8.self).contains("#EXTM3U") }) ?? false
            signal[h] = ok
        }
    }
}
