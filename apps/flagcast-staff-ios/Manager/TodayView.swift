import SwiftUI
import WebKit

/// Home (design MacHome, on a phone): a greeting over the course photo, the live (or next) tournament as one big
/// card with the ways in, three status tiles, Coming up, then the announcement and locking the results.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Group {
            if let d = model.current { DocHost(doc: d) { HomePage(doc: d) } }
            else { HomePage(doc: nil) }
        }
        .toolbar { ToolbarItem(placement: .topBarLeading) { AccountMenu() }; ToolbarItem(placement: .topBarTrailing) { TournamentMenu() } }
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
    f.type.isEmpty ? nil : f.name
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
        let td = ISO8601DateFormatter.day.string(from: Date()), isToday = ev.date == td || ev.rounds.contains { $0.date == td }
        // multi-day: "ROUND 2 OF 3 · SAT 12 JUN"
        let kick = doc.live.flatMap { l in Core.multiRound(l) ? (Core.roundName(l) + (Core.roundDay(l).isEmpty ? "" : " · \(Core.roundDay(l))")).uppercased() : nil } ?? (dayLine(ev.date) ?? "NO DATE SET")
        return PhotoPage(image: doc.picture.image, kicker: kick + (ev.locked ? " · FINAL" : ""), live: isToday && !ev.locked,
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
            if let live = doc.live, Core.multiRound(live) { RoundsCard(doc: doc, live: live) }
            PinSheetCard(doc: doc)
            CodesCard(doc: doc)
            InvitesCard(doc: doc)
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
    /// the board everyone sees (multi-day: the total over the rounds), and this round on its own (who's on the course)
    private func board(_ doc: DeskDoc) -> [Line] { doc.live.map { Core.board($0, $0.scores) } ?? [] }
    private func today(_ doc: DeskDoc) -> [Line] { doc.live.map { Core.leaderboard($0, $0.scores) } ?? [] }
    private func scoreText(_ ev: DeskEvent, _ l: Line) -> String { ev.format.isStableford ? "\(l.score)" : Core.fmtPar(l.score) }
    private func scoreColor(_ ev: DeskEvent, _ l: Line) -> Color { ev.format.isStableford ? FC.ink : l.score < 0 ? FC.red : l.score > 0 ? FC.blue : FC.ink }

    // ---- the four numbers (the Mac's Overview) ----
    private func stats(_ doc: DeskDoc) -> [StatCell] {
        let ev = doc.ev, live = doc.live, b = today(doc)
        let scoring = b.filter { $0.played > 0 && $0.thru != "F" }.count, finished = b.filter { $0.thru == "F" }.count
        let leader = board(doc).first { $0.played > 0 }
        let screens = ev.displays.count, on = ev.displays.filter { (live?.online[$0.id] ?? 0) > 0 }.count
        let most = b.map(\.played).max() ?? 0, behind = b.filter { most > 0 && $0.played < most - 2 }.count
        return [
            StatCell(label: "Teams", value: "\(ev.teams.count)", sub: "\(ev.teams.reduce(0) { $0 + $1.players.count }) players" + (ev.flights.count > 1 ? " · \(ev.flights.count) flights" : "")),
            StatCell(label: "On the course", value: "\(scoring)", sub: behind > 0 ? "\(behind) behind on scores" : finished > 0 ? "\(finished) finished" : (ev.locked ? "results final" : "scoring now"), color: behind > 0 ? FC.flag : FC.ink),
            StatCell(label: "Leader", value: leader.map { scoreText(ev, $0) } ?? "–", sub: leader.map { "\($0.name) · thru \($0.thru)" } ?? "No scores yet", color: leader.map { scoreColor(ev, $0) } ?? FC.ink),
            StatCell(label: "Screens", value: screens == 0 ? "–" : "\(on) / \(screens)", sub: screens == 0 ? "None set up" : ev.displays.prefix(2).map { $0.name.isEmpty ? "TV" : $0.name }.joined(separator: ", "), color: on > 0 ? FC.ok : FC.ink)
        ]
    }

    // ---- leaderboard (top 5); match play: the matches as they stand ----
    @ViewBuilder private func leaderboard(_ doc: DeskDoc) -> some View {
        if let live = doc.live, live.format.isMatch { matchList(doc, live) } else { strokeBoard(doc) }
    }
    private func matchList(_ doc: DeskDoc, _ live: EventState) -> some View {
        let all = Core.matches(live, live.scores), c = Core.cup(live, live.scores, all)
        let list = Array((all.filter { $0.started && !$0.done } + all.filter(\.done) + all.filter { !$0.started }).prefix(5))
        func nm(_ id: String) -> String { doc.ev.teams.first { $0.id == id }?.shortName ?? "" }
        return VStack(spacing: 0) {
            HStack {
                Text("Matches" + (c.on ? " · \(c.a) \(Core.fmtPts(c.A)), \(c.b) \(Core.fmtPts(c.B))" : "")).font(.system(size: 14, weight: .bold)).lineLimit(1)
                Spacer()
                Button("All scores ›") { tabs.tab = .scores }.font(.system(size: 13, weight: .semibold)).foregroundStyle(FC.link)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            if list.isEmpty {
                Text("Pair the teams on the Teams tab, then Save.").font(.callout).foregroundStyle(FC.muted).frame(maxWidth: .infinity).padding(.vertical, 26)
            }
            ForEach(list) { r in
                let w = r.winner ?? r.leader
                Rectangle().fill(FC.hairline).frame(height: 1)
                HStack(spacing: 6) {
                    Text(nm(r.a)).fontWeight(w == "A" ? .bold : .regular).lineLimit(1)
                    Text("v").foregroundStyle(FC.muted)
                    Text(nm(r.b)).fontWeight(w == "B" ? .bold : .regular).lineLimit(1)
                    Spacer()
                    Text(r.done ? "Final" : r.started ? "Thru \(r.thru)" : r.thru).font(.system(size: 12)).foregroundStyle(FC.muted)
                    Text(r.started ? r.text : "–").font(FC.display(22)).frame(minWidth: 44, alignment: .trailing)
                }
                .font(.system(size: 14))
                .padding(.horizontal, 14).padding(.vertical, 7)
            }
        }
        .background(FC.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FC.line))
    }
    private func strokeBoard(_ doc: DeskDoc) -> some View {
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
                    Text(l.thru == "F" || l.thru.hasPrefix("R") ? l.thru : "Thru \(l.thru)").font(.system(size: 12)).foregroundStyle(FC.muted)
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

/// The codes golfers and staff type on the join screen: the tournament code, each golf pro's and marshal's PIN,
/// and the way to the cart codes (on Links). Read-only here: PINs are changed on Pros & marshals.
/// One tap to today's pin sheet from Overview (club managers and admins; golf pros set pins in the phone app with their PIN).
struct PinSheetCard: View {
    let doc: DeskDoc
    var body: some View {
        let sheet = doc.live?.pinsheet ?? [:], holes = doc.live?.course.holes.count ?? 18
        NavigationLink { PinsScreen() } label: {
            ListRow(icon: "flag.fill", iconColor: FC.ok, title: "Pin sheet",
                    sub: sheet.isEmpty ? "Set where the pin is on each green today" : "\(sheet.count) of \(holes) pins set · golfers see them now", last: true) { Chevron() }
        }
        .buttonStyle(.plain)
        .card(padding: 0)
    }
}

struct CodesCard: View {
    let doc: DeskDoc
    var body: some View {
        CardBox(title: "Codes", footer: "Golfers type the tournament code and their cart code. Pros and marshals type the tournament code and their PIN.") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tournament code").font(.system(size: 12, weight: .semibold)).foregroundStyle(FC.muted)
                Text(doc.id.uppercased()).font(.system(size: 32, weight: .bold, design: .monospaced)).foregroundStyle(FC.ink).textSelection(.enabled)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(FC.hairline).frame(height: 1) }
            if doc.ev.pins.isEmpty {
                NavigationLink { WithTournament { StaffView(doc: $0) } } label: {
                    ListRow(icon: "person.badge.key.fill", iconColor: FC.blue, title: "No golf pros or marshals yet", sub: "Add them on Pros & marshals") { Chevron() }
                }
            }
            ForEach(doc.ev.pins) { p in
                ListRow(icon: p.role == "marshal" ? "flag.fill" : "person.badge.key.fill", iconColor: p.role == "marshal" ? FC.flag.opacity(0.9) : FC.blue,
                        title: p.name.isEmpty ? (p.role == "marshal" ? "Marshal" : "Golf pro") : p.name, sub: p.role == "marshal" ? "Marshal" : "Golf pro") {
                    Text("PIN \(p.pin)").font(.system(size: 16, weight: .semibold, design: .monospaced)).foregroundStyle(FC.ink).textSelection(.enabled)
                }
            }
            NavigationLink { WithTournament { LinksView(doc: $0) } } label: {
                ListRow(icon: "square.and.pencil", iconColor: FC.primary, title: "Cart codes", sub: "Each team’s code, on Links", last: true) { Chevron() }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Email invites (golf.js invite()): optional. Each player with an email (Teams) gets one email from the club with their
/// group, start and a link to their scorecard. The cart cards still work on the day.
struct InvitesCard: View {
    @Bindable var doc: DeskDoc
    @State private var sure = false
    @State private var testing = false
    @AppStorage("inviteTestTo") private var testTo = ""
    @State private var previewHTML: String?
    @State private var showAll = false

    var body: some View {
        let rows = Invites.rows(doc.ev), withEmail = rows.filter { Invites.ok($0.email) }.count, fresh = rows.filter(\.fresh).count
        let sent = rows.filter { $0.sent != nil }.count, first = sent == 0, club = doc.ev.club.isEmpty ? "the club" : doc.ev.club
        CardBox(title: "Email invites", footer: "Optional. Each player with an email gets one email from \(club) with their group, start and a link to their scorecard. Best sent a day or two before. The cart cards still work on the day.") {
            ListRow(icon: "envelope.fill", iconColor: FC.primary, title: "\(sent) of \(withEmail) invited",
                    sub: "\(withEmail) player\(withEmail == 1 ? " has" : "s have") an email · \(rows.count - withEmail) without") { EmptyView() }
            if doc.dirty { ListRow(icon: "exclamationmark.circle.fill", iconColor: FC.muted, title: "Save your changes first") { EmptyView() } }
            else if fresh > 0 {
                Button { sure = true } label: {
                    ListRow(icon: "paperplane.fill", iconColor: FC.green, title: first ? "Send invites to \(fresh) player\(fresh == 1 ? "" : "s")" : "Send to \(fresh) new player\(fresh == 1 ? "" : "s")",
                            sub: first ? "After this, it only sends to players added since" : nil) { if doc.inviteBusy { ProgressView() } else { Chevron() } }
                }
                .disabled(doc.inviteBusy)
            } else if withEmail == 0 {
                ListRow(icon: "person.crop.circle.badge.plus", iconColor: FC.blue, title: "Add emails on Teams", sub: "Tap a team, then type each player’s email") { EmptyView() }
            }
            Button { Task { previewHTML = await doc.invitePreview() } } label: { ListRow(icon: "eye.fill", iconColor: FC.blue, title: "Preview the email") { Chevron() } }
                .disabled(rows.isEmpty)
            Button { testing = true } label: { ListRow(icon: "envelope.badge.fill", iconColor: FC.blue, title: "Send me a test", last: rows.isEmpty) { Chevron() } }
                .disabled(rows.isEmpty)
            if !rows.isEmpty {
                DisclosureGroup(isExpanded: Binding(get: { showAll || sent > 0 }, set: { showAll = $0 })) {
                    ForEach(rows) { r in line(r, first: first) }
                } label: { Text("Who gets one (\(rows.count))").font(.system(size: 15, weight: .semibold)).foregroundStyle(FC.ink) }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
        }
        .buttonStyle(.plain)
        .confirmationDialog("Send \(fresh) invite\(fresh == 1 ? "" : "s") now?", isPresented: $sure, titleVisibility: .visible) {
            Button("Send \(fresh) Email\(fresh == 1 ? "" : "s")") { Task { await doc.sendInvites("new") } }
        } message: { Text("\(fresh) player\(fresh == 1 ? " gets" : "s get") one email each from \(club), through Flagcast. You can’t unsend them.") }
        .alert("Send a test invite", isPresented: $testing) {
            TextField("Your email", text: $testTo).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Send") { let to = testTo.trimmingCharacters(in: .whitespaces); Task { await doc.sendTestInvite(to: to) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("It’s the first player’s email, marked Test.") }
        .sheet(isPresented: Binding(get: { previewHTML != nil }, set: { if !$0 { previewHTML = nil } })) {
            NavigationStack {
                HTMLPreview(html: previewHTML ?? "").ignoresSafeArea(edges: .bottom)
                    .navigationTitle("The email").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { previewHTML = nil } } }
            }
        }
    }
    private func line(_ r: InviteRow, first: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.player.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(FC.ink)
                Text("\(r.group) · \(r.email.isEmpty ? "No email" : r.email)").font(.footnote).foregroundStyle(FC.muted).lineLimit(1)
                Text(r.sent.map { "Sent \(Invites.when($0.at))" } ?? (r.fresh ? (first ? "Not sent yet" : "Added since, not sent") : "Not sent"))
                    .font(.caption.weight(.semibold)).foregroundStyle(r.sent != nil ? FC.green : FC.muted)
            }
            Spacer(minLength: 8)
            if let m = r.sent, m.n < Invites.max { Button("Resend") { Task { await doc.sendInvites([r.player.id]) } }.buttonStyle(.bordered).controlSize(.small) }
            else if r.sent == nil && r.fresh { Button("Send") { Task { await doc.sendInvites([r.player.id]) } }.buttonStyle(.bordered).controlSize(.small) }
        }
        .padding(.vertical, 6)
        .disabled(doc.inviteBusy || doc.dirty)
    }
}

/// The invite email as players see it (a web view of the HTML)
private struct HTMLPreview: UIViewRepresentable {
    let html: String
    func makeUIView(context: Context) -> WKWebView { let w = WKWebView(); w.loadHTMLString(html, baseURL: URL(string: "https://flagcast.app")); return w }
    func updateUIView(_ w: WKWebView, context: Context) {}
}


/// Multi-day: each round with its date, which one the carts are scoring, and a button to play another round now
/// (two rounds on one day, or back a round to fix a card). Each morning the server moves on to that day's round by itself.
struct RoundsCard: View {
    @Bindable var doc: DeskDoc
    var live: EventState
    @State private var sure: Int?
    var body: some View {
        let now = Core.roundNow(live)
        CardBox(title: "Rounds", footer: "The carts score the round that’s playing now. Each morning the tournament moves on to that day’s round by itself. Going back a round keeps the later round’s scores.") {
            ForEach(0..<Core.roundCount(live), id: \.self) { i in
                if i > 0 { Divider().overlay(FC.hairline) }
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Round \(i + 1)" + (Core.roundDay(live, i).isEmpty ? "" : " · \(Core.roundDay(live, i))")).font(.system(size: 15, weight: .semibold))
                        Text(i == now ? (live.locked ? "Scoring now · locked" : "Scoring now") : live.past[i] == nil ? "Not started" : live.past[i]!.locked ? "Played · locked" : "Played")
                            .font(.system(size: 12)).foregroundStyle(i == now ? FC.ok : FC.muted)
                    }
                    Spacer()
                    if i != now {
                        Button(sure == i ? "Sure? Tap again" : "Play now") {
                            if sure == i { sure = nil; Task { await doc.playRound(i) } } else { sure = i }
                        }
                        .buttonStyle(.bordered).disabled(doc.dirty)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
        }
    }
}
