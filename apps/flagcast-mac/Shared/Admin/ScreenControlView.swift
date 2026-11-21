import SwiftUI

// Admin → Screens & phones (design MacAdminScreens): every club's TVs as cards grouped by club, with filters, a side
// panel to change one TV, the players' phones banner, and Engineering (the routing grid, scenes, take-overs).

/// One TV from Admin's point of view.
struct AdminTV: Identifiable, Hashable {
    let event: AdminEvent, tv: AdminEvent.Disp
    var id: String { "\(event.id)-\(tv.id)" }
    var on: Bool { tv.online > 0 }
    var temporary: Bool { tv.force?.isOn == true }
    var choices: PageChoices { PageChoices(flights: event.flights, p3: event.p3, sponsors: event.sponsors.map { ($0.id, $0.name) }) }
    var url: URL? { URL(string: "\(Server.base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/g/\(event.id)/board?screen=\(tv.id)") }
    var showing: String {
        if let f = tv.force, f.isOn { return choices.label(f) }
        return ShowTile.matching(tv.list)?.title ?? (tv.list.isEmpty ? "Everything" : "Own mix")
    }
}

struct ScreenControlView: View {
    @Environment(AdminModel.self) private var admin
    @Environment(AppModel.self) private var model
    @AppStorage("admin.screens.tab") private var tab = "tvs"
    @State private var club = ""
    @State private var filter = "all"
    @State private var search = ""
    @State private var picked: String?
    @State private var takingOver = false

    private var open: [AdminEvent] { admin.events.filter { !$0.gone && !$0.archived && !$0.hidden }.sorted { ($0.isToday ? 0 : 1, $1.created) < ($1.isToday ? 0 : 1, $0.created) } }
    private var allTVs: [AdminTV] { open.flatMap { e in e.displays.map { AdminTV(event: e, tv: $0) } } }
    private var shown: [AdminTV] {
        let q = search.lowercased()
        return allTVs.filter { t in
            (club.isEmpty || t.event.club == club) && (q.isEmpty || t.tv.name.lowercased().contains(q) || t.tv.place.lowercased().contains(q) || t.event.name.lowercased().contains(q)) &&
            (filter == "all" || (filter == "on" && t.on) || (filter == "off" && !t.on) || (filter == "temp" && t.temporary))
        }
    }
    private var clubs: [(String, String)] { var seen: [String: String] = [:]; for e in open where !e.club.isEmpty { seen[e.club] = e.clubName }; return seen.sorted { $0.value < $1.value }.map { ($0.key, $0.value) } }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    switch tab {
                    case "phones": PhonesPanel(events: open)
                    case "eng": EngineeringTab(events: open)
                    default: filters; tvGrid
                    }
                }
                .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 28)
            }
            if tab == "tvs", let id = picked, let t = allTVs.first(where: { $0.id == id }) {
                Divider()
                TVPanel(tv: t) { picked = nil }.frame(width: 330).id(t.id)
            }
        }
        .background(FC.paper)
        .sheet(isPresented: $takingOver) { TakeOverSheet(events: open.filter(\.isToday).isEmpty ? open : open.filter(\.isToday)) }
        .task { while !Task.isCancelled { await admin.refreshEvents(); try? await Task.sleep(for: .seconds(15)) } }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Screens & phones").font(FC.display(44))
            Picker("", selection: $tab) { Text("TVs").tag("tvs"); Text("Phones").tag("phones"); Text("Engineering").tag("eng") }
                .pickerStyle(.segmented).labelsHidden().frame(width: 280)
            Spacer()
            Menu {
                ForEach(open.prefix(15)) { e in Button("\(e.name) · \(e.clubName)") { model.openAdmin(id: e.id, key: e.key, name: e.name, date: e.date, club: e.clubName); model.section = .screens } }
            } label: { Label("Add a TV", systemImage: "plus") }
            .menuStyle(.button).fixedSize().help("Opens the tournament’s Screens page to add a TV")
            Button { takingOver = true } label: { Label("Take over screens", systemImage: "exclamationmark.triangle.fill") }
                .buttonStyle(RedButton())
        }
    }

    private var filters: some View {
        HStack(spacing: 10) {
            Picker("", selection: $club) { Text("All clubs").tag(""); ForEach(clubs, id: \.0) { Text($0.1).tag($0.0) } }.labelsHidden().frame(width: 180)
            chip("All", "all", allTVs.count)
            chip("On", "on", allTVs.filter(\.on).count)
            chip("Offline", "off", allTVs.filter { !$0.on }.count)
            chip("Showing something else", "temp", allTVs.filter(\.temporary).count)
            Spacer()
            TextField("Find a TV", text: $search).textFieldStyle(.roundedBorder).frame(width: 200)
        }
    }
    private func chip(_ t: String, _ v: String, _ n: Int) -> some View {
        Button { filter = v } label: {
            HStack(spacing: 5) { Text(t); Text("\(n)").foregroundStyle(filter == v ? FC.onGreen.opacity(0.8) : FC.muted) }
                .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 10).frame(height: 28)
                .foregroundStyle(filter == v ? FC.onGreen : FC.ink)
                .background(filter == v ? FC.green : FC.card, in: Capsule()).overlay(Capsule().stroke(filter == v ? .clear : FC.line))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var tvGrid: some View {
        if allTVs.isEmpty { Text(admin.events.isEmpty ? "Loading…" : "No club has added a TV yet.").foregroundStyle(FC.muted).frame(maxWidth: .infinity, minHeight: 200).raisedCard() }
        else if shown.isEmpty { Text("No TV matches.").foregroundStyle(FC.muted).frame(maxWidth: .infinity, minHeight: 120) }
        let groups = Dictionary(grouping: shown, by: { $0.event.club + "|" + $0.event.clubName })
        ForEach(groups.keys.sorted { $0.split(separator: "|").last ?? "" < $1.split(separator: "|").last ?? "" }, id: \.self) { k in
            let tvs = groups[k] ?? []
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(String(k.split(separator: "|").last ?? "No club")).font(FC.display(26))
                    if let live = tvs.first(where: { $0.event.isToday })?.event { LiveChip(); Text(live.name).font(.system(size: 13, weight: .semibold)) }
                    Text("\(tvs.count) TV\(tvs.count == 1 ? "" : "s")").font(.system(size: 13)).foregroundStyle(FC.muted)
                    Spacer()
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                    ForEach(tvs) { t in
                        Button { picked = t.id } label: { TVCard(tv: t, selected: picked == t.id) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct RedButton: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).padding(.horizontal, 14).frame(height: 30)
            .background(FC.red.opacity(c.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 7))
    }
}

/// A TV's card: 16:9 preview, status dot, name, where · what it shows, FOR 15 MIN on a temporary send.
private struct TVCard: View {
    let tv: AdminTV
    var selected = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                if tv.on { BigPreview(tv: tv) }
                else {
                    ZStack { Color(hex: 0x15201a); VStack(spacing: 4) { Image(systemName: "tv.slash").font(.system(size: 20)); Text("Offline").font(.system(size: 12, weight: .semibold)) }.foregroundStyle(.white.opacity(0.6)) }
                }
                if let f = tv.tv.force, f.isOn, f.until > 0 {
                    Text("FOR \(max(1, Int((f.until / 1000 - Date().timeIntervalSince1970) / 60 + 0.99))) MIN").font(.system(size: 10, weight: .bold)).tracking(0.6)
                        .padding(.horizontal, 6).padding(.vertical, 3).background(FC.flag, in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(FC.onFlag).padding(6)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 6) {
                Circle().fill(!tv.on ? FC.red : tv.temporary ? FC.flag : FC.ok).frame(width: 8, height: 8)
                Text(tv.tv.name.isEmpty ? "TV" : tv.tv.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            }
            Text([tv.tv.place.isEmpty ? nil : tv.tv.place, tv.showing].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(FC.muted).lineLimit(1)
        }
        .padding(10)
        .background(FC.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? FC.primary : .clear, lineWidth: 2))
        .shadow(color: FC.scrim.opacity(0.12), radius: 8, y: 4)
        .contentShape(Rectangle())
    }
}

/// A drawn picture of what a TV shows now.
private struct BigPreview: View {
    let tv: AdminTV
    var body: some View {
        ZStack {
            LinearGradient(colors: [FC.green2, FC.green], startPoint: .topLeading, endPoint: .bottomTrailing)
            let f = tv.tv.force?.isOn == true ? tv.tv.force : nil
            let k = f?.k ?? ShowTile.matching(tv.tv.list)?.pages.first?.k ?? "lb"
            VStack(spacing: 6) {
                Image(systemName: PageChoices.icon(k)).font(.system(size: 26, weight: .semibold)).foregroundStyle(f != nil ? FC.flag : FC.onGreen)
                Text(tv.showing).font(FC.display(18)).foregroundStyle(FC.onGreen).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(8)
        }
    }
}

/// The side panel for one TV: status, preview, what it shows normally, show something else, and the TV's settings.
private struct TVPanel: View {
    @Environment(AdminModel.self) private var admin
    let tv: AdminTV
    var close: () -> Void
    @State private var sending = false
    @State private var renaming = false
    @State private var moving = false
    @State private var text = ""
    @State private var confirmRemove = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Circle().fill(!tv.on ? FC.red : tv.temporary ? FC.flag : FC.ok).frame(width: 9, height: 9)
                    Text(tv.tv.name.isEmpty ? "TV" : tv.tv.name).font(FC.display(28)).lineLimit(1)
                    Spacer()
                    Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.borderless)
                }
                Text([tv.tv.place.isEmpty ? nil : tv.tv.place, tv.event.name, tv.on ? "On" : "Offline"].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(FC.muted)
                BigPreview(tv: tv).aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 10))
                Text(screenStatus(tv.tv.force, playlist: tv.tv.list, choices: tv.choices)).font(.system(size: 13))
                if tv.temporary {
                    Button("Back to Normal") { Task { await admin.day(tv.event.id, ["op": "screen", "display": tv.tv.id, "page": NSNull()], done: "Back to normal.") } }.buttonStyle(GreenButton())
                }
                CardTitle("What should this TV show?")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach([ShowTile.mix, .leaderboard, .camera, .sponsors]) { t in
                        let on = ShowTile.matching(tv.tv.list) == t
                        Button {
                            Task { await admin.editTVs(tv.event, done: "\(tv.tv.name) shows \(t.title) now.") { ds in if let i = ds.firstIndex(where: { $0.id == tv.tv.id }) { ds[i].playlist = t.pages } } }
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                VStack(spacing: 4) { Image(systemName: t.icon).font(.system(size: 18, weight: .semibold)); Text(t.title).font(.system(size: 12, weight: .semibold)) }
                                    .foregroundStyle(on ? FC.onGreen : FC.ink).frame(maxWidth: .infinity, minHeight: 66)
                                    .background(on ? FC.green : FC.paper2.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                                if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(FC.flag).padding(5) }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button("Show Something Else for a Bit…") { sending = true }.buttonStyle(PlainCardButton())
                    .popover(isPresented: $sending, arrowEdge: .leading) {
                        SendNowPanel(target: tv.tv.name.isEmpty ? "this TV" : tv.tv.name, choices: tv.choices) { page, mins in
                            var b: [String: Any] = ["op": "screen", "display": tv.tv.id, "page": pageDict(page)]
                            if mins > 0 { b["mins"] = mins }
                            Task { await admin.day(tv.event.id, b, done: mins > 0 ? "On \(tv.tv.name) for \(mins) minutes." : "On \(tv.tv.name) until you switch back.") }
                        }
                    }
                Divider()
                HStack(spacing: 6) {
                    Button("Rename") { text = tv.tv.name; renaming = true }
                    Button("Move") { text = tv.tv.place; moving = true }
                    Button("Copy TV Link") { if let u = tv.url { copy(u.absoluteString); admin.flash("TV link copied.") } }
                    Spacer()
                    Button("Remove", role: .destructive) { confirmRemove = true }
                }
                .controlSize(.small)
            }
            .padding(18)
        }
        .background(FC.card)
        .alert("Rename this TV", isPresented: $renaming) {
            TextField("Name", text: $text)
            Button("Rename") { let n = text; Task { await admin.editTVs(tv.event, done: "Renamed.") { ds in if let i = ds.firstIndex(where: { $0.id == tv.tv.id }) { ds[i].name = n } } } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Where is this TV?", isPresented: $moving) {
            TextField("Clubhouse, Bar, Pro shop…", text: $text)
            Button("Save") { let p = text; Task { await admin.editTVs(tv.event, done: "Moved.") { ds in if let i = ds.firstIndex(where: { $0.id == tv.tv.id }) { ds[i].place = p; ds[i].group = p } } } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Remove \(tv.tv.name) from \(tv.event.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove TV", role: .destructive) { Task { await admin.editTVs(tv.event, done: "Removed.") { ds in ds.removeAll { $0.id == tv.tv.id } }; close() } }
        }
    }
}

/// Players' phones: per tournament, the teams scoring on phones, what the phone banner shows, and sending one.
private struct PhonesPanel: View {
    @Environment(AdminModel.self) private var admin
    let events: [AdminEvent]
    @State private var text: [String: String] = [:]
    var body: some View {
        if events.isEmpty { Text("No open tournaments.").foregroundStyle(FC.muted).frame(maxWidth: .infinity, minHeight: 160).raisedCard() }
        ForEach(events) { e in
            let choices = PageChoices(flights: e.flights, p3: e.p3, sponsors: e.sponsors.map { ($0.id, $0.name) })
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    if e.isToday && !e.locked { LiveChip() }
                    Text(e.name).font(FC.display(26))
                    Text(e.clubName).font(.system(size: 13)).foregroundStyle(FC.muted)
                    Spacer()
                    Text("\(e.teams) teams · \(e.scored) scores in").font(.system(size: 12)).foregroundStyle(FC.muted)
                }
                if let p = e.phone {
                    HStack {
                        Label("Banner now: \(choices.label(PageRef(k: p.k, fl: p.fl, hole: p.hole, sponsor: p.sponsor)))\(p.text.isEmpty ? "" : " · “\(p.text)”")", systemImage: "iphone.gen3.radiowaves.left.and.right").foregroundStyle(FC.red)
                        Spacer()
                        Button("Clear") { Task { await admin.day(e.id, ["op": "screen", "display": "phones", "page": NSNull()], done: "Phones cleared.") } }
                    }
                    .font(.system(size: 13))
                }
                HStack {
                    TextField("Line on the banner (optional)", text: Binding(get: { text[e.id] ?? "" }, set: { text[e.id] = $0 })).textFieldStyle(.roundedBorder)
                    Menu("Send to Phones") {
                        ForEach([PageRef(k: "lb"), PageRef(k: "p3"), PageRef(k: "contests"), PageRef(k: "skins"), PageRef(k: "fund"), PageRef(k: "sponsors"), PageRef(k: "schedule")], id: \.k) { p in
                            Button(choices.label(p)) { let t = text[e.id] ?? ""; Task { await admin.day(e.id, ["op": "screen", "display": "phones", "page": pageDict(p), "text": t], done: "On every player’s phone.") } }
                        }
                        ForEach(e.p3, id: \.self) { h in Button("Par 3 camera · Hole \(h)") { let t = text[e.id] ?? ""; Task { await admin.day(e.id, ["op": "screen", "display": "phones", "page": pageDict(PageRef(k: "p3", hole: h)), "text": t], done: "On every player’s phone.") } } }
                    }
                    .fixedSize()
                }
            }
            .padding(18).raisedCard()
        }
    }
}

/// Engineering for one tournament: the TV × page grid, several TVs at once, take-overs, phones banner, scenes.
private struct EngineeringTab: View {
    @Environment(AdminModel.self) private var admin
    let events: [AdminEvent]
    @State private var eventId: String?
    private var e: AdminEvent? { events.first { $0.id == eventId } ?? events.first }
    var body: some View {
        Picker("Tournament", selection: Binding(get: { e?.id ?? "" }, set: { eventId = $0 })) {
            ForEach(events) { x in Text("\(x.name) · \(x.clubName)\(x.online > 0 ? " · \(x.online) TV\(x.online == 1 ? "" : "s") on" : "")").tag(x.id) }
        }
        .frame(maxWidth: 520)
        if let e { EngineeringView(src: engSource(e, admin)) } else { Text("No tournaments right now.").foregroundStyle(FC.muted) }
    }
}

@MainActor func engSource(_ e: AdminEvent, _ admin: AdminModel) -> EngSource {
    EngSource(
        tvs: e.displays.map { EngTV(id: $0.id, name: $0.name, place: $0.place, group: $0.group, online: $0.online, force: $0.force, playlist: $0.list) },
        choices: PageChoices(flights: e.flights, p3: e.p3, sponsors: e.sponsors.map { ($0.id, $0.name) }),
        url: { id in URL(string: "\(Server.base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/g/\(e.id)/board?screen=\(id)") },
        scenes: e.scenes.map { ($0.id, $0.name) }, currentScene: e.scene, take: e.take, phone: e.phone, announcement: e.flash,
        replays: e.replayList.map { ($0.id, "Hole \($0.hole) · \($0.label.isEmpty ? "Replay" : $0.label)") },
        day: { op, body, done in var b = body; b["op"] = op; await admin.day(e.id, b, done: done) })
}

/// "Take over screens": an announcement, hole in one, sponsor moment or replay on every TV of a tournament.
private struct TakeOverSheet: View {
    @Environment(AdminModel.self) private var admin
    @Environment(\.dismiss) private var dismiss
    let events: [AdminEvent]
    @State private var eventId: String?
    @State private var text = ""
    @State private var secs = 25
    private var e: AdminEvent? { events.first { $0.id == eventId } ?? events.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Take over screens").font(FC.display(32))
            Picker("Tournament", selection: Binding(get: { e?.id ?? "" }, set: { eventId = $0 })) { ForEach(events) { x in Text("\(x.name) · \(x.clubName)").tag(x.id) } }
            TextField("Message", text: $text, prompt: Text("Lunch is served at the turn")).textFieldStyle(.roundedBorder)
            Stepper("\(secs) seconds", value: $secs, in: 5...120, step: 5)
            if let e {
                HStack {
                    Button("Announce") { go(e, ["kind": "msg", "text": text, "secs": secs]) }.buttonStyle(GreenButton()).disabled(text.isEmpty)
                    Button("Hole in One!") { go(e, ["kind": "ace", "text": text, "secs": secs]) }.buttonStyle(RedButton())
                    if !e.sponsors.isEmpty { Menu("Sponsor Moment") { ForEach(e.sponsors) { s in Button(s.name) { go(e, ["kind": "sponsor", "sponsor": s.id, "secs": secs]) } } }.fixedSize() }
                    if !e.replayList.isEmpty { Menu("Replay") { ForEach(e.replayList) { r in Button("Hole \(r.hole) · \(r.label.isEmpty ? "Replay" : r.label)") { go(e, ["kind": "replay", "replay": r.id]) } } }.fixedSize() }
                }
                if let t = e.take { HStack { Text("Now: \(t.kind)\(t.text.map { " · \($0)" } ?? "")").foregroundStyle(FC.red); Spacer(); Button("Clear Take-over") { go(e, ["kind": "clear"]) } } }
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(24).frame(width: 560)
    }
    private func go(_ e: AdminEvent, _ b: [String: Any]) {
        var d = b; d["op"] = "take"
        Task { await admin.day(e.id, d, done: b["kind"] as? String == "clear" ? "Back to normal." : "On every TV now."); dismiss() }
    }
}
