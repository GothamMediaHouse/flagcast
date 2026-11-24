import SwiftUI

/// Admin (Flagcast staff, by admin email or the admin passcode): every club as a photo card with clubs waiting for
/// approval on top, every tournament, any club's TVs and players' phones (Engineering), activity, and More.
struct AdminHome: View {
    @Environment(AppModel.self) private var model
    @Environment(AdminModel.self) private var admin
    @State private var adding = false
    /// Admin (the Mac's design/Admin.dc.html, on a phone): a green header with the red ADMIN tag and New club, the
    /// sections as chips, then clubs asking to join and every club as a photo card.
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                ClubsView(embedded: true).padding(16).padding(.bottom, 80)
                    .frame(maxWidth: 980).frame(maxWidth: .infinity)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(FC.paper)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottom) { NoticeBar(text: admin.notice).padding(.bottom, 10).animation(.snappy, value: admin.notice) }
        .sheet(isPresented: $adding) { NavigationStack { NewClub() } }
        .task { try? await admin.refresh(); await admin.refreshEvents() }
        .refreshable { try? await admin.refresh(); await admin.refreshEvents() }
    }

    private var header: some View {
        let waiting = admin.clubs.filter { $0.status == "pending" }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Admin").font(FC.display(36))
                Text("ADMIN").font(.system(size: 10, weight: .bold)).tracking(1).padding(.horizontal, 6).padding(.vertical, 3).background(FC.red, in: RoundedRectangle(cornerRadius: 4))
                Spacer()
                Button { adding = true } label: { Label("New club", systemImage: "plus") }.buttonStyle(WhiteButton())
                AccountMenu(onGreen: true)
            }
            Text("\(admin.clubs.count) clubs · \(admin.events.filter { !$0.hidden && !$0.archived }.count) tournaments" + (waiting > 0 ? " · \(waiting) waiting" : ""))
                .font(.system(size: 13)).foregroundStyle(FC.onGreenMuted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("Event day", "sun.max") { ScrollView { EventDayList().padding(16) }.background(FC.paper).navigationTitle("Event day") }
                    chip("Tournaments", "flag.2.crossed") { AdminTournaments() }
                    chip("Screens", "tv.and.mediabox") { AdminScreens() }
                    chip("Cameras", "video") { AdminCameras() }
                    chip("Staff", "checkmark.shield") { AdminStaff() }
                    chip("Activity", "list.bullet.rectangle") { AdminActivity() }
                    chip("More", "ellipsis.circle") { MoreView() }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.top, 64).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FC.green)
    }
    private func chip<D: View>(_ title: String, _ icon: String, @ViewBuilder _ dest: () -> D) -> some View {
        NavigationLink { dest() } label: {
            Label(title, systemImage: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 12).frame(minHeight: 34)
                .background(Color.white.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Every club as a full-photo card; clubs asking to join on top, with Approve and Decline.
struct ClubsView: View {
    @Environment(AdminModel.self) private var admin
    /// inside Admin's home (no scroll view, search or toolbar of its own)
    var embedded = false
    @State private var search = ""
    @State private var opened: AdminClub?
    @State private var adding = false
    @AppStorage(ClubLook.key) private var look = ClubLook.photo
    private var shown: [AdminClub] {
        let q = search.lowercased()
        return admin.clubs.filter { q.isEmpty || $0.name.lowercased().contains(q) || $0.city.lowercased().contains(q) }
    }
    var body: some View {
        if embedded {
            list.sheet(item: $opened) { c in NavigationStack { ClubDetail(club: admin.clubs.first { $0.id == c.id } ?? c) } }
        } else {
            page
        }
    }
    private var page: some View {
        ScrollView { list.padding(16) }
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
    private var list: some View {
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
                Picker("Club cards", selection: $look) { ForEach(ClubLook.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 460), spacing: 14)], spacing: 14) {
                    ForEach(shown) { c in ClubCard(club: c) { opened = c } }
                }
                if shown.isEmpty { Text(admin.clubs.isEmpty ? "No clubs yet" : "No club matches").foregroundStyle(FC.muted).padding(30) }
            }
    }
}

/// One club as a photo card: status, name and town, tournaments left / made / staff, +1, +5, Open.
private struct ClubCard: View {
    @Environment(AdminModel.self) private var admin
    let club: AdminClub
    var open: () -> Void
    @State private var image: UIImage?
    @AppStorage(ClubLook.key) private var look = ClubLook.photo
    var body: some View {
        ZStack(alignment: .topLeading) {
            CourseHeroImage(image: image)
            if look == .logo { ClubLogoBackdrop(club: club) }
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
        .overlay(alignment: .topTrailing) { if look == .photo, let u = logoURL(club.logo) { ClubLogoTile(url: u, name: club.name, size: 60).padding(12) } }
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
    @State private var deleting = false
    @State private var newEvent = ""
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
            let live = admin.clubs.first { $0.id == club.id } ?? club
            CardBox(title: "Branding") {
                BrandingEditor(logo: logoURL(live.logo), accent: live.accent,
                               forWhat: "\(club.name)’s logo shows on its TVs, live page and the players’ app instead of the Flagcast logo. The club can change it in its own settings too.",
                               showPowered: true, powered: live.powered) { changes in await admin.brand(club.id, changes) }
                    .id(live.logo + live.accent + (live.powered ? "p" : ""))
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
            CardBox(title: "New tournament", footer: "Made by Flagcast, so it doesn’t use up one of the club’s tournaments.") {
                HStack(spacing: 8) {
                    BoxField(placeholder: "Name, e.g. Member-Guest 2027", text: $newEvent)
                    Button("Make") {
                        let n = newEvent
                        Task { await admin.act("event", ["club": club.id, "name": n], done: "Made \(n). It’s at the top of Tournaments below."); newEvent = "" }
                    }
                    .buttonStyle(GreenButton()).disabled(newEvent.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(14)
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
            if club.events.isEmpty {
                Button(role: .destructive) { deleting = true } label: { Label("Delete Club", systemImage: "trash").foregroundStyle(FC.red) }.buttonStyle(PlainCardButton(full: true))
            } else {
                Help("A club with tournaments can’t be deleted. Switch it off instead, or delete its tournaments in Admin → Tournaments.")
            }
        }
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .overlay(alignment: .bottom) { NoticeBar(text: admin.notice).padding(.bottom, 10).animation(.snappy, value: admin.notice) }
        .confirmationDialog("Delete \(club.name)?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete Club", role: .destructive) { Task { await admin.act("delete", ["club": club.id], done: "Club deleted."); if !admin.clubs.contains(where: { $0.id == club.id }) { dismiss() } } }
        } message: { Text("For a mistaken or spam sign-up. Its people lose access to it. This can’t be undone.") }
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
    @State private var deleting: AdminEvent?
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
                        ListRow(icon: "flag.fill", iconColor: e.locked || e.archived ? FC.muted : (e.online > 0 ? FC.ok : FC.primary), club: (admin.logo(for: e), e.clubName), title: e.name,
                                sub: [e.clubName, e.date, "\(e.teams) teams", e.screens > 0 ? "\(e.online)/\(e.screens) TVs on" : "", e.gone ? "Gone" : e.archived ? "Archived" : e.locked ? "Final" : e.hidden ? "Hidden" : ""].filter { !$0.isEmpty }.joined(separator: " · "),
                                last: i == shown.count - 1) {
                            if e.demo { DemoChip() }
                            Menu {
                                Button(e.demo ? "Stop Demo (Show the Club’s Logo)" : "Mark as Demo (Show the Flagcast Logo)") { Task { await admin.act("demo", ["id": e.id, "on": !e.demo], done: e.demo ? "Shows the club’s logo again." : "Marked Demo: it shows the Flagcast logo.") } }
                                Button(e.locked ? "Unlock Results" : "Lock Results") { Task { await admin.act("lock", ["id": e.id, "locked": !e.locked]) } }
                                Button(e.archived ? "Unarchive" : "Archive") { Task { await admin.act("archive", ["id": e.id, "on": !e.archived]) } }
                                Button(e.hidden ? "Show on the Club’s List" : "Hide from the Club’s List") { Task { await admin.act(e.hidden ? "unhide" : "hide", ["id": e.id]) } }
                                if !(e.hidden && e.archived) {
                                    Divider()
                                    Button("Delete Tournament…", role: .destructive) { deleting = e }
                                }
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
        .confirmationDialog("Delete \(deleting?.name ?? "this tournament")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { e in
            Button("Delete Tournament", role: .destructive) {
                Task {
                    if !e.archived { await admin.act("archive", ["id": e.id, "on": true]) }
                    await admin.act("hide", ["id": e.id], done: "Deleted. Turn on Show hidden and archived to bring it back.")
                }
            }
        } message: { _ in Text("It comes off the club’s list and its results are locked. Its scores stay, so you can bring it back from Show hidden and archived.") }
    }
}

/// Any club's TVs (grouped by club; tap one to change it), the players' phones banner, and Engineering.
private struct AdminScreens: View {
    @Environment(AdminModel.self) private var admin
    @State private var tab = "tvs"
    @State private var filter = "all"
    @State private var search = ""
    @State private var picked: PickedTV?
    @State private var eventId: String?
    struct PickedTV: Identifiable { var event: String, tv: String; var id: String { event + "-" + tv } }

    private var open: [AdminEvent] { admin.events.filter { !$0.gone && !$0.archived && !$0.hidden }.sorted { ($0.isToday ? 0 : 1, $1.created) < ($1.isToday ? 0 : 1, $0.created) } }
    private var tvs: [(AdminEvent, AdminEvent.Disp)] { open.flatMap { e in e.displays.map { (e, $0) } } }
    private var shown: [(AdminEvent, AdminEvent.Disp)] {
        let q = search.lowercased()
        return tvs.filter { e, d in
            (q.isEmpty || d.name.lowercased().contains(q) || d.place.lowercased().contains(q) || e.clubName.lowercased().contains(q)) &&
            (filter == "all" || (filter == "on" && d.online > 0) || (filter == "off" && d.online == 0) || (filter == "temp" && d.force?.isOn == true))
        }
    }
    private var engEvent: AdminEvent? { open.first { $0.id == eventId } ?? open.first }

    var body: some View {
        CardPage(kicker: "Admin", title: "Screens & phones", sub: "\(tvs.filter { $0.1.online > 0 }.count) of \(tvs.count) TVs on") {
            Picker("", selection: $tab) { Text("TVs").tag("tvs"); Text("Phones").tag("phones"); Text("Engineering").tag("eng") }.pickerStyle(.segmented)
            switch tab {
            case "phones": phones
            case "eng":
                Picker("Tournament", selection: Binding(get: { engEvent?.id ?? "" }, set: { eventId = $0 })) { ForEach(open) { x in Text("\(x.name) · \(x.clubName)").tag(x.id) } }
                    .pickerStyle(.menu).card(padding: 8)
                if let e = engEvent { EngineeringPanel(src: source(e)) }
            default:
                BoxField(placeholder: "Find a TV", text: $search)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip("All", "all", tvs.count); chip("On", "on", tvs.filter { $0.1.online > 0 }.count)
                        chip("Offline", "off", tvs.filter { $0.1.online == 0 }.count); chip("Something else", "temp", tvs.filter { $0.1.force?.isOn == true }.count)
                    }
                }
                let groups = Dictionary(grouping: shown, by: { $0.0.clubName.isEmpty ? "No club" : $0.0.clubName })
                if tvs.isEmpty { Text(admin.events.isEmpty ? "Loading…" : "No club has added a TV yet.").foregroundStyle(FC.muted).card() }
                ForEach(groups.keys.sorted(), id: \.self) { club in
                    let list = groups[club] ?? []
                    CardBox(title: "\(club) · \(list.count) TV\(list.count == 1 ? "" : "s")") {
                        ForEach(Array(list.enumerated()), id: \.offset) { i, p in
                            let (e, d) = p
                            let choices = PageChoices(flights: e.flights, p3: e.p3, sponsors: e.sponsors.map { ($0.id, $0.name) })
                            let showing = d.force?.isOn == true ? choices.label(d.force!) : (ShowTile.matching(d.list)?.title ?? (d.list.isEmpty ? "Everything" : "Own mix"))
                            Button { picked = PickedTV(event: e.id, tv: d.id) } label: {
                                ListRow(icon: d.online > 0 ? "tv.fill" : "tv.slash", iconColor: d.online == 0 ? FC.red : d.force?.isOn == true ? FC.flag : FC.ok,
                                        title: d.name.isEmpty ? "TV" : d.name, sub: [d.place.isEmpty ? nil : d.place, d.online > 0 ? showing : "Offline", e.name].compactMap { $0 }.joined(separator: " · "),
                                        last: i == list.count - 1) {
                                    if let f = d.force, f.isOn, f.until > 0 {
                                        Text("\(max(1, Int((f.until / 1000 - Date().timeIntervalSince1970) / 60 + 0.99))) MIN").font(.system(size: 10, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 3)
                                            .background(FC.flag, in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(FC.onFlag)
                                    }
                                    Chevron()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .overlay(alignment: .bottom) { NoticeBar(text: admin.notice).padding(.bottom, 10).animation(.snappy, value: admin.notice) }
        .sheet(item: $picked) { p in
            if let e = admin.events.first(where: { $0.id == p.event }), let d = e.displays.first(where: { $0.id == p.tv }) { NavigationStack { AdminTVSheet(event: e, tv: d) } }
        }
        .task { while !Task.isCancelled { await admin.refreshEvents(); try? await Task.sleep(for: .seconds(15)) } }
    }

    private func chip(_ t: String, _ v: String, _ n: Int) -> some View {
        Button { filter = v } label: {
            Text("\(t) \(n)").font(.subheadline.weight(.semibold)).padding(.horizontal, 12).frame(minHeight: 34)
                .foregroundStyle(filter == v ? FC.onGreen : FC.ink).background(filter == v ? FC.green : FC.card, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var phones: some View {
        ForEach(open) { e in
            let choices = PageChoices(flights: e.flights, p3: e.p3, sponsors: e.sponsors.map { ($0.id, $0.name) })
            VStack(alignment: .leading, spacing: 8) {
                HStack { if e.isToday && !e.locked { LiveChip() }; Text(e.name).font(FC.display(22)).lineLimit(1) }
                Text("\(e.clubName) · \(e.teams) teams · \(e.scored) scores in").font(.caption).foregroundStyle(FC.muted)
                if let p = e.phone {
                    HStack { Text("Banner now: \(choices.label(PageRef(k: p.k, fl: p.fl, hole: p.hole, sponsor: p.sponsor)))").font(.footnote).foregroundStyle(FC.red); Spacer()
                        Button("Clear") { Task { await admin.day(e.id, ["op": "screen", "display": "phones", "page": NSNull()], done: "Phones cleared.") } }.font(.footnote) }
                }
                Menu {
                    ForEach([PageRef(k: "lb"), PageRef(k: "p3"), PageRef(k: "contests"), PageRef(k: "skins"), PageRef(k: "fund"), PageRef(k: "sponsors"), PageRef(k: "schedule")], id: \.k) { p in
                        Button(choices.label(p)) { Task { await admin.day(e.id, ["op": "screen", "display": "phones", "page": pageDict(p)], done: "On every player’s phone.") } }
                    }
                } label: { Text("Send to Phones…").frame(maxWidth: .infinity) }
                .buttonStyle(GreenButton(full: true))
            }
            .card()
        }
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

/// One TV from Admin: what it shows now, what it shows normally (tiles), show something else, rename, move, link, remove.
private struct AdminTVSheet: View {
    @Environment(AdminModel.self) private var admin
    @Environment(\.dismiss) private var dismiss
    let event: AdminEvent
    let tv: AdminEvent.Disp
    @State private var sending = false
    @State private var name = ""
    @State private var place = ""
    @State private var confirmRemove = false
    private var choices: PageChoices { PageChoices(flights: event.flights, p3: event.p3, sponsors: event.sponsors.map { ($0.id, $0.name) }) }
    var body: some View {
        CardPage(kicker: "\(event.clubName) · \(event.name)", title: tv.name.isEmpty ? "TV" : tv.name, sub: tv.online > 0 ? screenStatus(tv.force, playlist: tv.list, choices: choices) : "Offline") {
            HStack(spacing: 8) {
                if tv.force?.isOn == true { Button("Back to Normal") { Task { await admin.day(event.id, ["op": "screen", "display": tv.id, "page": NSNull()], done: "Back to normal.") } }.buttonStyle(GreenButton(full: true)) }
                Button("Show Something Else…") { sending = true }.buttonStyle(PlainCardButton(full: true))
            }
            CardBox(title: "What should this TV show?") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach([ShowTile.mix, .leaderboard, .camera, .sponsors]) { t in
                        let on = ShowTile.matching(tv.list) == t
                        Button { Task { await admin.editTVs(event, done: "Shows \(t.title) now.") { ds in if let i = ds.firstIndex(where: { $0.id == tv.id }) { ds[i].playlist = t.pages } } } } label: {
                            ZStack(alignment: .topTrailing) {
                                VStack(spacing: 4) { Image(systemName: t.icon).font(.system(size: 20, weight: .semibold)); Text(t.title).font(.system(size: 13, weight: .semibold)) }
                                    .foregroundStyle(on ? FC.onGreen : FC.ink).frame(maxWidth: .infinity, minHeight: 76)
                                    .background(on ? FC.green : FC.paper2.opacity(0.7), in: RoundedRectangle(cornerRadius: 11))
                                if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(FC.flag).padding(6) }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
            CardBox(title: "This TV") {
                VStack(spacing: 10) {
                    HStack { BoxField(placeholder: "Name", text: $name); Button("Rename") { let n = name; Task { await admin.editTVs(event, done: "Renamed.") { ds in if let i = ds.firstIndex(where: { $0.id == tv.id }) { ds[i].name = n } } } }.disabled(name == tv.name) }
                    HStack { BoxField(placeholder: "Where is it?", text: $place); Button("Move") { let p = place; Task { await admin.editTVs(event, done: "Moved.") { ds in if let i = ds.firstIndex(where: { $0.id == tv.id }) { ds[i].place = p; ds[i].group = p } } } }.disabled(place == tv.place) }
                    HStack {
                        if let u = URL(string: "\(Server.base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/g/\(event.id)/board?screen=\(tv.id)") {
                            ShareLink(item: u) { Label("TV Link", systemImage: "square.and.arrow.up") }
                        }
                        Spacer()
                        Button("Remove", role: .destructive) { confirmRemove = true }
                    }
                }
                .padding(12)
            }
        }
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onAppear { name = tv.name; place = tv.place }
        .sheet(isPresented: $sending) {
            SendSheet(target: tv.name.isEmpty ? "this TV" : tv.name, choices: choices, places: []) { page, mins, _ in
                var b: [String: Any] = ["op": "screen", "display": tv.id, "page": pageDict(page)]
                if mins > 0 { b["mins"] = mins }
                Task { await admin.day(event.id, b, done: mins > 0 ? "On \(tv.name) for \(mins) minutes." : "On \(tv.name) until you switch back.") }
            }
        }
        .confirmationDialog("Remove \(tv.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove TV", role: .destructive) { Task { await admin.editTVs(event, done: "Removed.") { ds in ds.removeAll { $0.id == tv.id } }; dismiss() } }
        }
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

/// Who gets Admin when they sign in (the Mac and web Admin's Staff). ADMIN_EMAIL ones are listed but changed in Cloudflare.
private struct AdminStaff: View {
    @Environment(AdminModel.self) private var admin
    @State private var email = ""
    @State private var removing: StaffMember?
    var body: some View {
        CardPage(kicker: "Admin", title: "Staff", sub: "\(admin.staff.count) with Admin") {
            Text("Anyone here gets Admin, on the iPhone, iPad, Mac and web, when they sign in with that email. Club owners never see Admin.")
                .font(.footnote).foregroundStyle(FC.muted)
            CardBox {
                if admin.staff.isEmpty { Text("Only the passcode opens Admin.").foregroundStyle(FC.muted).padding(14) }
                ForEach(Array(admin.staff.enumerated()), id: \.element.id) { i, m in
                    ListRow(icon: m.fixed ? "lock.fill" : "person.fill", iconColor: m.fixed ? FC.muted : FC.primary, title: m.email, sub: detail(m), last: i == admin.staff.count - 1) {
                        if !m.fixed { Button("Remove") { removing = m }.font(.subheadline.weight(.semibold)).foregroundStyle(FC.red) }
                    }
                }
            }
            CardBox {
                HStack {
                    TextField("name@example.com", text: $email).keyboardType(.emailAddress).textContentType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().onSubmit(add)
                    Button("Add", action: add).font(.body.weight(.semibold)).disabled(!email.contains("@"))
                }
                .padding(14)
            }
        }
        .confirmationDialog("Take \(removing?.email ?? "") off staff? They lose Admin.", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove from staff", role: .destructive) { if let m = removing { Task { await admin.act("staff-remove", ["email": m.email], done: "Removed from staff.") } } }
        }
        .overlay(alignment: .bottom) { NoticeBar(text: admin.notice).padding(.bottom, 10).animation(.snappy, value: admin.notice) }
        .task { try? await admin.refresh() }
        .refreshable { try? await admin.refresh() }
    }
    private func add() {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines); guard e.contains("@") else { return }
        Task { await admin.act("staff-add", ["email": e], done: "Added. They get Admin the next time they sign in."); if admin.staff.contains(where: { $0.email == e.lowercased() }) { email = "" } }
    }
    private func detail(_ m: StaffMember) -> String {
        let seen = m.seen > 0 ? Date(timeIntervalSince1970: m.seen / 1000).formatted(date: .abbreviated, time: .shortened) : "never"
        return "\(m.fixed ? "Set in Cloudflare" : "Added \(Date(timeIntervalSince1970: m.added / 1000).formatted(date: .abbreviated, time: .omitted))") · signed in \(seen)"
    }
}
