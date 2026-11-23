import SwiftUI

/// Home (design MacHome, on a phone): a greeting over the course photo, the live (or next) tournament as one big
/// card with the ways in, three status tiles, Coming up, then the announcement and locking the results.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Group {
            if let d = model.current { DocHost(doc: d) { HomePage(doc: d) } }
            else { HomePage(doc: nil) }
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { TournamentMenu() } }
    }
}

/// Which tournament Home leads with: today's, else the next, else the latest.
@MainActor func featured(_ events: [EventRef]) -> EventRef? {
    let today = ISO8601DateFormatter.day.string(from: Date())
    if let t = events.first(where: { $0.date == today }) { return t }
    if let next = events.filter({ ($0.date ?? "") > today }).min(by: { ($0.date ?? "") < ($1.date ?? "") }) { return next }
    return events.max { ($0.added ?? 0) < ($1.added ?? 0) } ?? events.first
}
func stepsLeft(_ ev: DeskEvent) -> [String] {
    var out: [String] = []
    if ev.date.isEmpty { out.append("Set the date") }
    if ev.course.name.isEmpty { out.append("Pick the course") }
    if ev.teams.isEmpty { out.append("Add teams") }
    if ev.displays.isEmpty { out.append("Add a TV") }
    return out
}
func formatName(_ f: Format) -> String? {
    ["bestball": "Best ball", "scramble": "Scramble", "stableford": "Stableford", "stroke": "Stroke play", "match": "Match play"][f.type] ?? (f.type.isEmpty ? nil : f.type.capitalized)
}

private struct HomePage: View {
    @Environment(AppModel.self) private var model
    @Environment(Tabs.self) private var tabs
    let doc: DeskDoc?
    @State private var flash = ""
    @State private var confirmLock = false
    @State private var adding = false
    @State private var making = false

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let part = h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
        return model.firstName.isEmpty ? part : "\(part), \(model.firstName)"
    }
    private var coming: [EventRef] {
        let today = ISO8601DateFormatter.day.string(from: Date())
        return model.shownEvents.filter { $0.id != doc?.id && (($0.date ?? "") >= today || ($0.date ?? "").isEmpty) }.sorted { ($0.date ?? "9999") < ($1.date ?? "9999") }
    }

    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var horizontal

    var body: some View {
        Group {
            if let doc { page(doc) } else { emptyPage }
        }
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh(); if let doc { await doc.feed.refresh(); await doc.refreshDay() } }
        .onAppear { if model.selection == nil, let f = featured(model.shownEvents) { model.selection = f.id } }
        .sheet(isPresented: $adding) { NavigationStack { AddByLinkView() } }
        .sheet(isPresented: $making) { NavigationStack { TournamentPicker(asSheet: true) } }
        .confirmationDialog("Lock the results?", isPresented: $confirmLock, titleVisibility: .visible) {
            Button("Lock Results") { if let doc { Task { await doc.setLocked(true) } } }
        } message: { Text("Scoring closes on every scorecard and the leaderboard becomes final. You can unlock again.") }
    }

    /// Overview (the Mac's design/Main.dc.html): the course photo with LIVE · date, the name and the course line,
    /// the frosted numbers on the photo's edge, the leaderboard and the closest-to-the-pin tile, then the day's tools.
    private func page(_ doc: DeskDoc) -> some View {
        let ev = doc.ev
        let isToday = ev.date == ISO8601DateFormatter.day.string(from: Date())
        return PhotoPage(image: doc.picture.image, kicker: (dayLine(ev.date) ?? "NO DATE SET") + (ev.locked ? " · FINAL" : ""), live: isToday && !ev.locked,
                         title: ev.name.isEmpty ? doc.ref.name : ev.name, sub: subtitle(ev), height: 380) {
            if let u = logoURL(doc.live?.brand.logo) { RemoteLogo(url: u).frame(width: 160, height: 40, alignment: .leading).shadow(color: .black.opacity(0.3), radius: 6) }
            HStack(spacing: 8) {
                Button { openURL(doc.boardURL) } label: { Label("Open the board", systemImage: "tv") }.buttonStyle(WhiteButton())
                Button { adding = true } label: { Label("Add by link", systemImage: "link") }.buttonStyle(GlassButton())
                if model.me?.club?.canMake == true { Button { making = true } label: { Image(systemName: "plus").accessibilityLabel("New tournament") }.buttonStyle(GlassButton()) }
            }
        } content: {
            StatsStrip(cells: stats(doc), columns: horizontal == .regular ? 4 : 2).padding(.top, -6)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) { leaderboard(doc).frame(minWidth: 380); contestTile(doc).frame(width: 300) }
                VStack(spacing: 14) { leaderboard(doc); contestTile(doc).frame(height: 190) }
            }
            // on the day: the checks with their fixes (they cover what the status card shows on other days)
            if DayOfChecks.isEventDay(doc) { DayOfChecks(doc: doc) { tabs.tab = .screens }.card(padding: 16) } else { tiles(doc) }
            if !coming.isEmpty {
                CardBox(title: "Coming up") { ForEach(Array(coming.prefix(6).enumerated()), id: \.element.id) { i, e in ComingRow(ref: e, last: i == min(coming.count, 6) - 1) } }
            }
            announce(doc); lockButton(doc)
        }
    }

    private var emptyPage: some View {
        PhotoPage(image: nil, kicker: [model.me?.club?.name, model.me?.club?.city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "), title: greeting, height: 260) {
            if let u = logoURL(model.me?.club?.logo) { RemoteLogo(url: u).frame(width: 160, height: 40, alignment: .leading).shadow(color: .black.opacity(0.3), radius: 6) }
            HStack(spacing: 8) {
                Button { adding = true } label: { Label("Add by link", systemImage: "link") }.buttonStyle(GlassButton())
                if model.me?.club?.canMake == true { Button { making = true } label: { Label("New", systemImage: "plus") }.buttonStyle(WhiteButton()) }
            }
        } content: {
            VStack(spacing: 10) {
                Image(systemName: "flag.2.crossed").font(.system(size: 30)).foregroundStyle(FC.muted)
                Text("No tournaments yet").font(FC.display(28))
                Text("Make one, or add one you were sent a link for.").font(.subheadline).foregroundStyle(FC.muted)
            }
            .frame(maxWidth: .infinity).card(padding: 24)
            if !coming.isEmpty {
                CardBox(title: "Coming up") { ForEach(Array(coming.prefix(6).enumerated()), id: \.element.id) { i, e in ComingRow(ref: e, last: i == min(coming.count, 6) - 1) } }
            }
        }
    }

    private func subtitle(_ ev: DeskEvent) -> String {
        let holes = ev.course.holes.filter { ev.playHoles.contains($0.n) }
        let nine = ev.format.nine == "front" ? "Front 9" : ev.format.nine == "back" ? "Back 9" : "18 holes"
        let par = holes.reduce(0) { $0 + $1.par }, yds = holes.reduce(0) { $0 + $1.yds }
        return [ev.course.name.isEmpty ? (ev.club.isEmpty ? nil : ev.club) : ev.course.name, holes.isEmpty ? nil : nine, par > 0 ? "Par \(par)" : nil,
                yds > 0 ? "\(ev.course.tees.first.map { "\($0.name) tees " } ?? "")\(yds.formatted()) yds" : nil, formatName(ev.format)].compactMap { $0 }.joined(separator: " · ")
    }
    private func board(_ doc: DeskDoc) -> [Line] { doc.live.map { Core.leaderboard($0, $0.scores) } ?? [] }
    private func scoreText(_ ev: DeskEvent, _ l: Line) -> String { ev.format.isStableford ? "\(l.score)" : Core.fmtPar(l.score) }
    private func scoreColor(_ ev: DeskEvent, _ l: Line) -> Color { ev.format.isStableford ? FC.ink : l.score < 0 ? FC.red : l.score > 0 ? FC.blue : FC.ink }

    // ---- the four numbers (the Mac's Overview) ----
    private func stats(_ doc: DeskDoc) -> [StatCell] {
        let ev = doc.ev, live = doc.live, b = board(doc)
        let scoring = b.filter { $0.played > 0 && $0.thru != "F" }.count, finished = b.filter { $0.thru == "F" }.count
        let leader = b.first { $0.played > 0 }
        let screens = ev.displays.count, on = ev.displays.filter { (live?.online[$0.id] ?? 0) > 0 }.count
        let most = b.map(\.played).max() ?? 0, behind = b.filter { most > 0 && $0.played < most - 2 }.count
        return [
            StatCell(label: "Teams", value: "\(ev.teams.count)", sub: "\(ev.teams.reduce(0) { $0 + $1.players.count }) players" + (ev.flights.count > 1 ? " · \(ev.flights.count) flights" : "")),
            StatCell(label: "On the course", value: "\(scoring)", sub: behind > 0 ? "\(behind) behind on scores" : finished > 0 ? "\(finished) finished" : (ev.locked ? "results final" : "scoring now"), color: behind > 0 ? FC.flag : FC.ink),
            StatCell(label: "Leader", value: leader.map { scoreText(ev, $0) } ?? "–", sub: leader.map { "\($0.name) · thru \($0.thru)" } ?? "No scores yet", color: leader.map { scoreColor(ev, $0) } ?? FC.ink),
            StatCell(label: "Screens", value: screens == 0 ? "–" : "\(on) / \(screens)", sub: screens == 0 ? "None set up" : ev.displays.prefix(2).map { $0.name.isEmpty ? "TV" : $0.name }.joined(separator: ", "), color: on > 0 ? FC.ok : FC.ink)
        ]
    }

    // ---- leaderboard (top 5) ----
    private func leaderboard(_ doc: DeskDoc) -> some View {
        let ev = doc.ev, top = Array(board(doc).filter { $0.played > 0 }.prefix(5))
        return VStack(spacing: 0) {
            HStack {
                Text("Leaderboard").font(.system(size: 14, weight: .bold))
                Spacer()
                Button("All scores ›") { tabs.tab = .scores }.font(.system(size: 13, weight: .semibold)).foregroundStyle(FC.link)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            if top.isEmpty {
                Text(ev.teams.isEmpty ? "Add teams on the Teams tab, then Save." : "Scores show here as the carts send them.")
                    .font(.callout).foregroundStyle(FC.muted).frame(maxWidth: .infinity).padding(.vertical, 26)
            }
            ForEach(top) { l in
                Rectangle().fill(FC.hairline).frame(height: 1)
                HStack(spacing: 10) {
                    Text(l.pos).font(.system(size: 14, weight: .bold)).foregroundStyle(FC.muted).frame(width: 28, alignment: .leading)
                    Text(l.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Text(l.thru == "F" ? "F" : "Thru \(l.thru)").font(.system(size: 12)).foregroundStyle(FC.muted)
                    Text(scoreText(ev, l)).font(FC.display(22)).foregroundStyle(scoreColor(ev, l)).frame(minWidth: 40, alignment: .trailing)
                }
                .padding(.horizontal, 14).padding(.vertical, 7)
            }
        }
        .background(FC.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FC.line))
    }

    // ---- closest to the pin ----
    private func contestTile(_ doc: DeskDoc) -> some View {
        let ev = doc.ev, all = doc.live?.contests ?? ev.contests
        let c = all.first { !$0.isLongDrive } ?? all.first
        let lead = c.flatMap { Core.contestLeader($0).first }
        return ZStack(alignment: .bottomLeading) {
            Color.clear.overlay {
                if let c { HolePicture(id: doc.id, n: c.hole, h: ev.map.holes[c.hole], fallback: doc.picture.image) } else { CourseHeroImage(image: doc.picture.image) }
            }
            .clipped()
            LinearGradient(colors: [FC.scrim.opacity(0.88), FC.scrim.opacity(0)], startPoint: .bottom, endPoint: .init(x: 0.5, y: 0.3))
            VStack(alignment: .leading, spacing: 2) {
                Text(c.map { "\($0.isLongDrive ? "LONG DRIVE" : "CLOSEST TO THE PIN") · HOLE \($0.hole)" } ?? "CONTESTS").font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(FC.flag)
                Text(lead?.name ?? (c == nil ? "No contests yet" : "No results yet")).font(FC.display(28)).lineLimit(1).minimumScaleFactor(0.6)
                Text(lead.flatMap { l in c.map { Core.fmtDist($0, l.dist) } }.map { d in d + (c?.sponsor.isEmpty == false ? " · presented by \(c!.sponsor)" : "") }
                     ?? (c == nil ? "Add one in More → Contests." : "Marshals post results from the phone app."))
                    .font(.system(size: 13)).foregroundStyle(Color(hex: 0xdfe8e1)).lineLimit(1)
            }
            .foregroundStyle(.white).padding(.horizontal, 16).padding(.bottom, 14)
        }
        .frame(minHeight: 190)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func num(_ v: String, _ l: String, color: Color = FC.ink) -> some View {
        VStack(alignment: .leading, spacing: 0) { Text(v).font(FC.display(28)).foregroundStyle(color); Text(l).font(.caption).foregroundStyle(FC.muted).lineLimit(1) }
    }

    /// TVs on, par 3 cameras (Flagcast's; read only), teams scoring on phones.
    @ViewBuilder private func tiles(_ doc: DeskDoc) -> some View {
        let ev = doc.ev, live = doc.live
        let tvs = ev.displays, on = tvs.filter { (live?.online[$0.id] ?? 0) > 0 }
        let p3 = ev.course.holes.filter { $0.par == 3 && ev.playHoles.contains($0.n) }.map(\.n)
        let cams = p3.filter { !(live?.cams[$0] ?? ev.cams[$0] ?? "").isEmpty }
        let scoring = live.map { s in s.teams.filter { t in (s.scores[t.id] ?? [:]).values.contains { $0.contains { $0 != nil } } }.count } ?? 0
        if !tvs.isEmpty || !p3.isEmpty || !ev.teams.isEmpty {
            CardBox {
                if !tvs.isEmpty {
                    ListRow(icon: "tv.fill", iconColor: on.count == tvs.count ? FC.ok : FC.flag, title: "\(on.count) of \(tvs.count) TVs on",
                            sub: tvs.first { (live?.online[$0.id] ?? 0) == 0 }.map { "\($0.name.isEmpty ? "A TV" : $0.name) is off" } ?? "All showing Flagcast")
                }
                if !p3.isEmpty { ListRow(icon: "video.fill", iconColor: cams.isEmpty ? FC.muted : FC.ok, title: "\(cams.count) of \(p3.count) par 3 cameras", sub: "Set up by Flagcast") }
                if !ev.teams.isEmpty { ListRow(icon: "iphone", iconColor: scoring > 0 ? FC.ok : FC.muted, title: "\(scoring) of \(ev.teams.count) teams scoring", sub: scoring > 0 ? "On their phones" : "None yet", last: true) }
            }
        }
    }

    private func announce(_ doc: DeskDoc) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle("Announcement on every TV")
            if let f = doc.live?.flash, !f.text.isEmpty {
                HStack { Text("“\(f.text)”").foregroundStyle(FC.muted); Spacer(); Button("Clear") { Task { await doc.day("flash", ["text": ""], done: "Cleared.") } } }
            }
            HStack {
                TextField("Shotgun start in 10 minutes", text: $flash).padding(10).background(FC.paper2, in: RoundedRectangle(cornerRadius: 9))
                Button("Show") { let t = flash; Task { if await doc.day("flash", ["text": t], done: "On every TV now.") != nil { flash = "" } } }.buttonStyle(GreenButton()).disabled(flash.isEmpty)
            }
        }
        .card()
    }
    private func lockButton(_ doc: DeskDoc) -> some View {
        Button { if doc.ev.locked { Task { await doc.setLocked(false) } } else { confirmLock = true } } label: {
            Label(doc.ev.locked ? "Unlock the results" : "Lock the results", systemImage: doc.ev.locked ? "lock.open" : "lock.fill")
        }
        .buttonStyle(PlainCardButton(full: true))
    }
}

private struct ComingRow: View {
    @Environment(AppModel.self) private var model
    let ref: EventRef
    var last = false
    @State private var steps: [String]?
    var body: some View {
        Button { model.selection = ref.id } label: {
            ListRow(icon: "calendar", iconColor: FC.green2, title: ref.name, sub: [ref.date.flatMap(dayLine), steps.map { $0.isEmpty ? "Ready" : "\($0.count) step\($0.count == 1 ? "" : "s") left" }].compactMap { $0 }.joined(separator: " · "), last: last) {
                if let steps {
                    Text(steps.isEmpty ? "READY" : "\(steps.count) LEFT").font(.system(size: 10, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 3)
                        .background(steps.isEmpty ? FC.ok.opacity(0.15) : FC.flag.opacity(0.3), in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(steps.isEmpty ? FC.ok : FC.onFlag)
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: ref.id) { if let ev = try? await Net.deskGet(ref.id, ref.key) { steps = stepsLeft(ev) } }
    }
}

/// Signed in with no club yet (and not Flagcast staff): set up my club, or I was sent a link.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var settingUp = false
    @State private var adding = false
    var body: some View {
        CardPage(kicker: model.me?.email, title: "Welcome to Flagcast", sub: "How would you like to start?", height: 300) {
            Button { settingUp = true } label: { choice("building.2.fill", "Set up my club", "Tell us your club. Flagcast approves it and emails you.") }.buttonStyle(.plain)
            Button { adding = true } label: { choice("link", "I was sent a link", "Paste a tournament’s desk link to open it.") }.buttonStyle(.plain)
            Button("Not you? Sign out") { Task { await model.signOut() } }.font(.subheadline).foregroundStyle(FC.muted).frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $settingUp) { NavigationStack { ClubRequestView() } }
        .sheet(isPresented: $adding) { NavigationStack { AddByLinkView() } }
    }
    private func choice(_ icon: String, _ t: String, _ sub: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white).frame(width: 52, height: 52).background(FC.green, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 3) { Text(t).font(FC.display(26)).foregroundStyle(FC.ink); Text(sub).font(.subheadline).foregroundStyle(FC.muted) }
            Spacer()
            Image(systemName: "arrow.right").font(.headline).foregroundStyle(FC.link)
        }
        .card(padding: 18)
    }
}

private struct ClubRequestView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var contact = ""
    @State private var phone = ""
    @State private var city = ""
    @State private var err: String?
    var body: some View {
        CardPage(kicker: "Welcome", title: "Set up my club", sub: "Flagcast approves it and emails you.") {
            VStack(spacing: 10) {
                BoxField(placeholder: "Club name", text: $name)
                BoxField(placeholder: "Your name", text: $contact).textContentType(.name)
                BoxField(placeholder: "Phone", text: $phone).keyboardType(.phonePad)
                BoxField(placeholder: "Town and state", text: $city)
                if let err { Text(err).font(.footnote).foregroundStyle(FC.red) }
                Button("Send to Flagcast") {
                    Task { do { try await model.club("request", ["name": name, "contact": contact, "phone": phone, "city": city]); await model.refresh(); dismiss() } catch { err = error.localizedDescription } }
                }
                .buttonStyle(GreenButton(full: true)).disabled(name.isEmpty)
            }
            .card()
        }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
}

extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
