import SwiftUI

// Home for club staff (design MacHome): a greeting over the course photo, the live (or next) tournament in one big
// card, three status tiles, and what's coming up. First sign-in with no club: WelcomeView (design MacWelcome).

/// Which of the club's tournaments Home leads with: today's, else the next one, else the latest.
@MainActor func featured(_ events: [EventRef]) -> EventRef? {
    let today = ISO8601DateFormatter.day.string(from: Date())
    if let t = events.first(where: { $0.date == today }) { return t }
    if let next = events.filter({ ($0.date ?? "") > today }).min(by: { ($0.date ?? "") < ($1.date ?? "") }) { return next }
    return events.max { ($0.added ?? 0) < ($1.added ?? 0) } ?? events.first
}

/// What's left before a tournament is ready (from its desk setup).
func stepsLeft(_ ev: DeskEvent) -> [String] {
    var out: [String] = []
    if ev.date.isEmpty { out.append("Set the date") }
    if ev.course.name.isEmpty { out.append("Pick the course") }
    if ev.teams.isEmpty { out.append("Add teams") }
    if ev.displays.isEmpty { out.append("Add a TV") }
    return out
}

struct HomeDashboard: View {
    @Environment(AppModel.self) private var model
    @State private var adding = false
    @State private var making = false

    private var lead: EventRef? { featured(model.shownEvents) }
    private var doc: DeskDoc? { lead.flatMap { model.doc($0.id) } }
    private var coming: [EventRef] {
        let today = ISO8601DateFormatter.day.string(from: Date())
        return model.shownEvents.filter { $0.id != lead?.id && (($0.date ?? "") >= today || ($0.date ?? "").isEmpty) }
            .sorted { ($0.date ?? "9999") < ($1.date ?? "9999") }
    }
    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let part = h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
        return model.firstName.isEmpty ? part : "\(part), \(model.firstName)"
    }

    var body: some View {
        PhotoPage(image: doc?.picture.image, height: 300, section: "Home", titleHeight: 196) {
            Button { adding = true } label: { Label("Add by link", systemImage: "link") }.buttonStyle(GlassButton())
            Button { making = true } label: { Label("New tournament", systemImage: "plus") }.buttonStyle(WhiteButton()).disabled(!(model.me?.club?.canMake ?? false))
        } title: {
            HeroTitle(kicker: [model.me?.club?.name, model.me?.club?.city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ").nilIfEmpty ?? "Flagcast Manager",
                      title: greeting, size: 64, sub: model.me?.club?.stateLine)
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let lead, let doc { LeadCard(ref: lead, doc: doc); StatusTiles(doc: doc) }
                    else { emptyCard }
                    if !coming.isEmpty {
                        CardTitle("Coming up")
                        VStack(spacing: 0) {
                            ForEach(coming.prefix(8)) { e in ComingRow(ref: e) }
                        }
                        .raisedCard()
                    }
                    if let club = model.me?.club { PeopleCard(club: club) }
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
        .task(id: lead?.id) { if let doc, !doc.loaded { await doc.load() }; if let doc { doc.picture.load(doc.ev, id: doc.id) } }
        .onChange(of: model.focusNew) { _, on in if on { making = true; model.focusNew = false } }
        .onChange(of: model.focusAdd) { _, on in if on { adding = true; model.focusAdd = false } }
        .sheet(isPresented: $adding) { AddLinkSheet() }
        .sheet(isPresented: $making) { NewTournamentSheet() }
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "flag.2.crossed").font(.system(size: 34)).foregroundStyle(FC.muted)
            Text("No tournaments yet").font(FC.display(30))
            Text(model.me?.club?.canMake == true ? "Make your first one, or add one you were sent." : (model.me?.club?.stateLine ?? "Add a tournament you were sent a link for."))
                .foregroundStyle(FC.muted).multilineTextAlignment(.center)
            HStack {
                Button("Add by Link") { adding = true }.buttonStyle(PlainCardButton())
                if model.me?.club?.canMake == true { Button("New Tournament") { making = true }.buttonStyle(GreenButton()) }
            }
        }
        .padding(30).frame(maxWidth: .infinity).raisedCard()
    }
}

/// The live (or next) tournament: photo, LIVE, name and format, four numbers, and the ways in.
private struct LeadCard: View {
    @Environment(AppModel.self) private var model
    let ref: EventRef
    @Bindable var doc: DeskDoc
    private var ev: DeskEvent { doc.ev }
    private var board: [Line] { doc.live.map { Core.leaderboard($0, $0.scores) } ?? [] }
    private var isToday: Bool { (ref.date ?? ev.date) == ISO8601DateFormatter.day.string(from: Date()) }

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                CourseHeroImage(image: doc.picture.image)
                if isToday && !ev.locked { LiveChip().padding(12) }
            }
            .frame(width: 300).frame(minHeight: 230).clipped()
            VStack(alignment: .leading, spacing: 12) {
                Text((dayLine(ev.date) ?? "NO DATE SET") + (ev.locked ? " · FINAL" : "")).font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(FC.muted)
                Text(ev.name.isEmpty ? ref.name : ev.name).font(FC.display(36)).lineLimit(1).minimumScaleFactor(0.6)
                Text([ev.course.name.isEmpty ? nil : ev.course.name, formatName(ev.format)].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 13)).foregroundStyle(FC.muted)
                if doc.loaded {
                    HStack(spacing: 22) {
                        num("\(ev.teams.count)", "teams")
                        let played = board.reduce(0) { $0 + $1.played }
                        if played > 0 { num("\(played)", "holes played") }
                        if let l = board.first(where: { $0.played > 0 }) { num(ev.format.isStableford ? "\(l.score)" : Core.fmtPar(l.score), l.name, color: l.score < 0 && !ev.format.isStableford ? FC.red : FC.ink) }
                        let most = board.map(\.played).max() ?? 0
                        let behind = board.filter { most > 0 && $0.played < most - 2 }.count
                        if behind > 0 { num("\(behind)", "behind on scores", color: FC.flag) }
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Button("Open Tournament") { go(.overview) }.buttonStyle(GreenButton())
                    Button("Scores") { go(.scores) }.buttonStyle(PlainCardButton())
                    Button("Screens") { go(.screens) }.buttonStyle(PlainCardButton())
                    Button("Teams") { go(.teams) }.buttonStyle(PlainCardButton())
                }
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(FC.card).clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: FC.scrim.opacity(0.18), radius: 15, y: 8)
        .padding(.top, 4)
    }
    private func num(_ v: String, _ l: String, color: Color = FC.ink) -> some View {
        VStack(alignment: .leading, spacing: 0) { Text(v).font(FC.display(30)).foregroundStyle(color); Text(l).font(.system(size: 12)).foregroundStyle(FC.muted).lineLimit(1) }
    }
    private func go(_ s: Section) { model.selection = ref.id; model.section = s }
}

/// TVs on, par 3 cameras (set up by Flagcast; read only), players scoring on phones. Hidden when there's nothing to say.
private struct StatusTiles: View {
    let doc: DeskDoc
    var body: some View {
        let ev = doc.ev, live = doc.live
        let tvs = ev.displays, on = tvs.filter { (live?.online[$0.id] ?? 0) > 0 }
        let p3 = ev.course.holes.filter { $0.par == 3 && ev.playHoles.contains($0.n) }.map(\.n)
        let cams = p3.filter { !(live?.cams[$0] ?? ev.cams[$0] ?? "").isEmpty }
        let scoring = live.map { s in s.teams.filter { t in (s.scores[t.id] ?? [:]).values.contains { $0.contains { $0 != nil } } }.count } ?? 0
        HStack(spacing: 14) {
            if !tvs.isEmpty {
                tile("tv", on.count == tvs.count ? FC.ok : FC.flag, "\(on.count) of \(tvs.count)", "TVs on",
                     tvs.first { (live?.online[$0.id] ?? 0) == 0 }.map { "\($0.name.isEmpty ? "A TV" : $0.name) is off" } ?? "All showing Flagcast")
            }
            if !p3.isEmpty {
                tile("video", cams.isEmpty ? FC.muted : FC.ok, "\(cams.count) of \(p3.count)", "par 3 cameras", "Set up by Flagcast")
            }
            if !ev.teams.isEmpty {
                tile("iphone", scoring > 0 ? FC.ok : FC.muted, "\(scoring) of \(ev.teams.count)", "teams scoring on phones", scoring > 0 ? "Scores coming in" : "None yet")
            }
        }
    }
    private func tile(_ icon: String, _ color: Color, _ value: String, _ label: String, _ sub: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).frame(width: 34, height: 34).background(color, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) { Text(value).font(FC.display(28)); Text(label).font(.system(size: 13, weight: .semibold)) }
                Text(sub).font(.system(size: 12)).foregroundStyle(FC.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity).raisedCard()
    }
}

/// One coming-up tournament: date, name, club or course, and READY or N STEPS LEFT.
private struct ComingRow: View {
    @Environment(AppModel.self) private var model
    let ref: EventRef
    @State private var steps: [String]?
    var body: some View {
        Button { model.selection = ref.id; model.section = .overview } label: {
            HStack(spacing: 14) {
                VStack(spacing: 0) {
                    Text(monthDay.0).font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(FC.red)
                    Text(monthDay.1).font(FC.display(24))
                }
                .frame(width: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ref.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(steps.map { $0.isEmpty ? "All set" : $0.joined(separator: " · ") } ?? (ref.club ?? "")).font(.system(size: 12)).foregroundStyle(FC.muted).lineLimit(1)
                }
                Spacer()
                if let steps {
                    Text(steps.isEmpty ? "READY" : "\(steps.count) STEP\(steps.count == 1 ? "" : "S") LEFT").font(.system(size: 10, weight: .bold)).tracking(0.8)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(steps.isEmpty ? FC.ok.opacity(0.15) : FC.flag.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(steps.isEmpty ? FC.ok : FC.onFlag)
                }
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(FC.muted)
            }
            .padding(.horizontal, 16).padding(.vertical, 10).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(FC.hairline).frame(height: 1) }
        .task(id: ref.id) { if let ev = try? await Net.deskGet(ref.id, ref.key) { steps = stepsLeft(ev) } }
    }
    private var monthDay: (String, String) {
        guard let s = ref.date, let d = ISO8601DateFormatter.day.date(from: s) else { return ("", "–") }
        return (d.formatted(.dateTime.month(.abbreviated)).uppercased(), d.formatted(.dateTime.day()))
    }
}

/// The club's people (owners can add and remove).
private struct PeopleCard: View {
    @Environment(AppModel.self) private var model
    let club: ClubMe.Club
    @State private var invite = ""
    @State private var err: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle("People who can run \(club.name)’s tournaments")
            ForEach(model.me?.members ?? [], id: \.self) { m in
                HStack {
                    Text(m.email).font(.system(size: 13)); if m.role == "owner" { Text("owner").font(.system(size: 12)).foregroundStyle(FC.muted) }
                    Spacer()
                    if model.me?.isOwner == true && m.role != "owner" {
                        Button("Remove", role: .destructive) { Task { do { try await model.club("uninvite", ["email": m.email]); await model.refresh() } catch { err = error.localizedDescription } } }.buttonStyle(.borderless)
                    }
                }
            }
            if model.me?.isOwner == true {
                HStack {
                    TextField("name@yourclub.com", text: $invite).textFieldStyle(.roundedBorder)
                    Button("Add") { Task { do { try await model.club("invite", ["email": invite]); invite = ""; await model.refresh() } catch { err = error.localizedDescription } } }.disabled(invite.isEmpty)
                }
            }
            if let err { Text(err).foregroundStyle(FC.red).font(.callout) }
        }
        .padding(18).raisedCard()
    }
}

// MARK: - sheets

struct AddLinkSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var err: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a tournament by its link").font(FC.display(28))
            Text("Paste the desk link you were sent. It ends in a long key after a # sign.").foregroundStyle(FC.muted)
            TextField("https://flagcast.app/g/…/desk#…", text: $link).textFieldStyle(.roundedBorder).onSubmit(add)
            if let err { Text(err).foregroundStyle(FC.red).font(.callout) }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Add", action: add).buttonStyle(GreenButton()).keyboardShortcut(.defaultAction).disabled(link.isEmpty) }
        }
        .padding(24).frame(width: 520)
    }
    private func add() { err = nil; Task { do { try await model.add(link: link); dismiss() } catch { err = error.localizedDescription } } }
}

struct NewTournamentSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var err: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New tournament").font(FC.display(28))
            if let c = model.me?.club { Text(c.stateLine).foregroundStyle(FC.muted) }
            TextField("Member-Guest 2027", text: $name).textFieldStyle(.roundedBorder).onSubmit(make)
            if let err { Text(err).foregroundStyle(FC.red).font(.callout) }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Make Tournament", action: make).buttonStyle(GreenButton()).keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
        }
        .padding(24).frame(width: 460)
    }
    private func make() { err = nil; Task { do { try await model.create(name.trimmingCharacters(in: .whitespaces)); dismiss() } catch { err = error.localizedDescription } } }
}

// MARK: - first sign-in

/// Signed in with no club yet (and not Flagcast staff): set up my club, or I was sent a link.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var settingUp = false
    @State private var adding = false
    var body: some View {
        ZStack {
            CourseHeroImage(image: nil).overlay(FC.scrim.opacity(0.35))
            Image(systemName: "flag.fill").font(.system(size: 520)).foregroundStyle(.white.opacity(0.04)).offset(x: 260, y: 60)
            VStack(spacing: 26) {
                FlagcastMark(size: 64)
                VStack(spacing: 8) {
                    Text("Welcome to Flagcast").font(FC.display(64)).foregroundStyle(.white)
                    Text("Signed in as \(model.me?.email ?? ""). How would you like to start?").font(.system(size: 16)).foregroundStyle(.white.opacity(0.85))
                }
                HStack(spacing: 18) {
                    choice("building.2.fill", "Set up my club", "Tell us your club. Flagcast approves it and emails you, then you can make tournaments.") { settingUp = true }
                    choice("link", "I was sent a link", "Someone gave you a tournament’s desk link. Paste it to open that tournament.") { adding = true }
                }
                Button("Not you? Sign out") { Task { await model.signOut() } }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.8))
            }
            .padding(40)
        }
        .ignoresSafeArea()
        .sheet(isPresented: $settingUp) { ClubRequestSheet() }
        .sheet(isPresented: $adding) { AddLinkSheet() }
    }
    private func choice(_ icon: String, _ title: String, _ sub: String, _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.system(size: 26, weight: .semibold)).foregroundStyle(.white).frame(width: 54, height: 54).background(FC.green, in: RoundedRectangle(cornerRadius: 14))
                Text(title).font(FC.display(30)).foregroundStyle(FC.ink)
                Text(sub).font(.system(size: 14)).foregroundStyle(FC.muted).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack { Spacer(); Image(systemName: "arrow.right").font(.system(size: 16, weight: .bold)).foregroundStyle(FC.link) }
            }
            .padding(24).frame(width: 320, height: 250, alignment: .topLeading)
            .background(FC.card, in: RoundedRectangle(cornerRadius: 18)).shadow(color: .black.opacity(0.25), radius: 20, y: 10).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ClubRequestSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var req = ClubRequest()
    @State private var err: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set up my club").font(FC.display(30))
            Text("Flagcast approves it and emails you.").foregroundStyle(FC.muted)
            Form {
                TextField("Club name", text: $req.name, prompt: Text("Willow Creek Country Club"))
                TextField("Your name", text: $req.contact)
                TextField("Phone", text: $req.phone)
                TextField("Town and state", text: $req.city, prompt: Text("Rye, NY"))
            }
            .formStyle(.grouped).scrollContentBackground(.hidden).frame(height: 220)
            if let err { Text(err).foregroundStyle(FC.red).font(.callout) }
            HStack {
                Spacer(); Button("Cancel") { dismiss() }
                Button("Send to Flagcast") {
                    Task { do { try await model.club("request", ["name": req.name, "contact": req.contact, "phone": req.phone, "city": req.city]); await model.refresh(); dismiss() } catch { err = error.localizedDescription } }
                }
                .buttonStyle(GreenButton()).keyboardShortcut(.defaultAction).disabled(req.name.isEmpty)
            }
        }
        .padding(24).frame(width: 520)
    }
}

extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }

func formatName(_ f: Format) -> String? {
    ["bestball": "Best ball", "scramble": "Scramble", "stableford": "Stableford", "stroke": "Stroke play", "match": "Match play"][f.type] ?? (f.type.isEmpty ? nil : f.type.capitalized)
}
