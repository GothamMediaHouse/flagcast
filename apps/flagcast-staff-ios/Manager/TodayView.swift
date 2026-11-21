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

    var body: some View {
        PhotoPage(image: doc?.picture.image, kicker: [model.me?.club?.name, model.me?.club?.city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                  title: greeting, height: 260) {
            // the club's own logo, once it has one (Settings → Your club)
            if let u = logoURL(model.me?.club?.logo) { RemoteLogo(url: u).frame(width: 160, height: 40, alignment: .leading).shadow(color: .black.opacity(0.3), radius: 6) }
            HStack(spacing: 8) {
                Button { adding = true } label: { Label("Add by link", systemImage: "link") }.buttonStyle(WhiteButton())
                if model.me?.club?.canMake == true { Button { making = true } label: { Label("New", systemImage: "plus") }.buttonStyle(WhiteButton()) }
            }
        } content: {
            if let doc { lead(doc); tiles(doc) }
            else {
                VStack(spacing: 10) {
                    Image(systemName: "flag.2.crossed").font(.system(size: 30)).foregroundStyle(FC.muted)
                    Text("No tournaments yet").font(FC.display(28))
                    Text("Make one, or add one you were sent a link for.").font(.subheadline).foregroundStyle(FC.muted)
                }
                .frame(maxWidth: .infinity).card(padding: 24)
            }
            if !coming.isEmpty {
                CardBox(title: "Coming up") { ForEach(Array(coming.prefix(6).enumerated()), id: \.element.id) { i, e in ComingRow(ref: e, last: i == min(coming.count, 6) - 1) } }
            }
            if let doc { announce(doc); lockButton(doc) }
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

    /// The live (or next) tournament: photo, LIVE, name and format, numbers, and the ways in.
    private func lead(_ doc: DeskDoc) -> some View {
        let ev = doc.ev
        let board = doc.live.map { Core.leaderboard($0, $0.scores) } ?? []
        let isToday = ev.date == ISO8601DateFormatter.day.string(from: Date())
        let played = board.reduce(0) { $0 + $1.played }, most = board.map(\.played).max() ?? 0
        let behind = board.filter { most > 0 && $0.played < most - 2 }.count
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                CourseHeroImage(image: doc.picture.image).frame(height: 130).clipped()
                if isToday && !ev.locked { LiveChip().padding(10) }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text((dayLine(ev.date) ?? "NO DATE SET") + (ev.locked ? " · FINAL" : "")).font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(FC.muted)
                Text(ev.name.isEmpty ? doc.ref.name : ev.name).font(FC.display(32)).lineLimit(2).minimumScaleFactor(0.6)
                if let f = [ev.course.name.isEmpty ? nil : ev.course.name, formatName(ev.format)].compactMap({ $0 }).joined(separator: " · ").nilIfEmpty { Text(f).font(.subheadline).foregroundStyle(FC.muted) }
                HStack(spacing: 18) {
                    num("\(ev.teams.count)", "teams")
                    if played > 0 { num("\(played)", "holes played") }
                    if let l = board.first(where: { $0.played > 0 }) { num(ev.format.isStableford ? "\(l.score)" : Core.fmtPar(l.score), l.name, color: l.score < 0 && !ev.format.isStableford ? FC.red : FC.ink) }
                    if behind > 0 { num("\(behind)", "behind", color: FC.flag) }
                }
                HStack(spacing: 8) {
                    Button("Scores") { tabs.tab = .scores }.buttonStyle(GreenButton(full: true))
                    Button("Screens") { tabs.tab = .screens }.buttonStyle(PlainCardButton(full: true))
                    Button("Teams") { tabs.tab = .teams }.buttonStyle(PlainCardButton(full: true))
                }
            }
            .padding(16)
        }
        .background(FC.card, in: RoundedRectangle(cornerRadius: 14)).clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: FC.scrim.opacity(0.12), radius: 12, y: 5)
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
