import SwiftUI

/// The club's TVs with the Flagcast TV app (Apple TV, Google TV, Fire TV, Roku) or a TV browser at flagcast.app/tv
/// (tv.js on the server). They belong to the club, not to one tournament: add one once with the code it shows and it
/// plays the tournament of the day by itself, as one of that tournament's TVs. Shared by the Mac and iPhone/iPad Managers.
struct ClubTV: Decodable, Identifiable, Hashable {
    var id: String, name: String, `where`: String, kind: String, on: Bool
    /// the tournament it always shows ('' = the tournament of the day)
    var event: String = "", eventName: String = ""
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); name = (try? c.decode(String.self, forKey: .name)) ?? "TV"
        `where` = (try? c.decode(String.self, forKey: .where)) ?? ""; kind = (try? c.decode(String.self, forKey: .kind)) ?? ""
        on = (try? c.decode(Bool.self, forKey: .on)) ?? false
        event = (try? c.decode(String.self, forKey: .event)) ?? ""; eventName = (try? c.decode(String.self, forKey: .eventName)) ?? ""
    }
    enum CodingKeys: String, CodingKey { case id, name, `where`, kind, on, event, eventName }
    var kindName: String { ["appletv": "Apple TV", "androidtv": "Google TV", "firetv": "Fire TV", "roku": "Roku"][kind] ?? "TV browser" }
}

@MainActor @Observable
final class ClubTVs {
    var list: [ClubTV] = []
    var loaded = false
    var error: String?
    private struct Answer: Decodable { var tvs: [ClubTV]; var added: Int?; var tv: ClubTV? }

    /// The server makes every club TV one of this tournament's screens when it's asked from here: when one is new, its
    /// card shows (the setup reloads, keeping unsaved edits).
    @discardableResult
    private func call(_ op: String, _ doc: DeskDoc, _ extra: [String: Any] = [:]) async throws -> Answer {
        var b = extra; b["id"] = doc.id; b["key"] = doc.key
        let d = try await Net.post("/golf/api/tv/\(op)", b)
        let a = try JSONDecoder().decode(Answer.self, from: d)
        let missing = a.tvs.contains { t in !doc.ev.displays.contains { $0.id == t.id } }
        if (a.added ?? 0) > 0 || (missing && doc.loaded) { await doc.refreshDay() }
        list = a.tvs
        return a
    }
    func tv(_ id: String) -> ClubTV? { list.first { $0.id == id } }
    func load(_ doc: DeskDoc) async {
        do { try await call("list", doc); error = nil } catch { self.error = (error as? APIError)?.message ?? error.localizedDescription }
        loaded = true
    }
    /// Connect the TV showing this code (it joins this tournament at once). Throws with a message to show.
    func add(_ doc: DeskDoc, code: String, name: String, place: String) async throws -> ClubTV {
        let a = try await call("add", doc, ["code": code, "name": name, "where": place])
        guard let t = a.tv else { throw APIError(status: 0, message: "That didn’t work. Try again.") }
        return t
    }
    /// A new name and place, for this TV in every tournament.
    func edit(_ doc: DeskDoc, _ id: String, name: String, place: String) async {
        do { try await call("edit", doc, ["tv": id, "name": name, "where": place]) } catch { doc.flash((error as? APIError)?.message ?? "That didn’t work.") }
    }
    func rename(_ doc: DeskDoc, _ tv: ClubTV, name: String) async {
        do { try await call("edit", doc, ["tv": tv.id, "name": name]) } catch { doc.flash((error as? APIError)?.message ?? "That didn’t work.") }
    }
    /// Always show this tournament on it (nil: back to the tournament of the day)
    func pin(_ doc: DeskDoc, _ tv: ClubTV, _ on: Bool) async {
        do { try await call("edit", doc, ["tv": tv.id, "event": on ? doc.id : ""])
             doc.flash(on ? "\(tv.name) always shows this tournament now." : "\(tv.name) shows the tournament of the day.") }
        catch { doc.flash((error as? APIError)?.message ?? "That didn’t work.") }
    }
    func remove(_ doc: DeskDoc, _ tv: ClubTV) async {
        do { try await call("remove", doc, ["tv": tv.id]); await doc.refreshDay(); doc.flash("\(tv.name) is removed. It shows a new code.") } catch { doc.flash((error as? APIError)?.message ?? "That didn’t work.") }
    }
}


// MARK: - shared by the Mac and iPhone/iPad Managers' Screens pages: one list of TVs, a page per TV, and Add a TV

/// The places a TV can be, offered as chips and in the Where is it? menu (plus any the club has used).
let TV_PLACES = ["Clubhouse", "Bar", "Grill room", "Pro shop", "Tent", "Patio", "Locker room", "Hole 7 tee", "Hole 18 green"]

/// Switch one TV, a list of TVs or every TV ("*"); page nil = back to normal.
@MainActor func sendToTVs(_ doc: DeskDoc, _ display: Any, _ page: PageRef?, _ mins: Int, to: String) {
    if let ids = display as? [String], ids.isEmpty { doc.flash("No TVs there yet."); return }
    var b: [String: Any] = ["display": display, "page": pageDict(page)]
    if page != nil, mins > 0 { b["mins"] = mins }
    let done = page == nil ? "Back to normal: \(to)." : mins > 0 ? "On \(to) for \(mins) minutes." : "On \(to) until you switch back."
    Task { await doc.day("screen", b, done: done) }
}

extension DeskDoc {
    /// every place a TV is at in this tournament, then the usual ones
    var tvPlaces: [String] {
        var seen: [String] = []
        for d in ev.displays where !d.place.isEmpty && !seen.contains(where: { $0.caseInsensitiveCompare(d.place) == .orderedSame }) { seen.append(d.place) }
        return TV_PLACES + seen.filter { p in !TV_PLACES.contains { $0.caseInsensitiveCompare(p) == .orderedSame } }
    }
    var tvsOn: Int { ev.displays.filter { (live?.online[$0.id] ?? 0) > 0 }.count }
    func tvURL(_ id: String) -> URL { URL(string: "\(boardURL.absoluteString)?screen=\(id)")! }
}

/// What's on the TV: picks the help text in Add a TV (the TV itself says what it is once it's connected).
enum TVKind: String, CaseIterable, Identifiable {
    case appletv, google, roku, web
    var id: String { rawValue }
    var title: String { switch self { case .appletv: "Apple TV"; case .google: "Google TV or Fire TV"; case .roku: "Roku"; case .web: "Smart TV or computer" } }
    var icon: String { switch self { case .appletv: "appletv"; case .google: "play.tv"; case .roku: "tv"; case .web: "globe" } }
    var getIt: String {
        switch self {
        case .appletv, .google, .roku: "With the Flagcast TV app"
        case .web: "Open flagcast.app/tv in its web browser"
        }
    }
    var open: String {
        switch self {
        case .appletv: "On the Apple TV, open Flagcast TV. It shows a code like this:"
        case .google: "On the TV, open Flagcast TV. It shows a code like this:"
        case .roku: "On the Roku, open Flagcast TV. It shows a code like this:"
        case .web: "In the TV’s web browser, go to flagcast.app/tv. It shows a code like this:"
        }
    }
    var defaultName: String { switch self { case .appletv: "Apple TV"; case .google: "Google TV"; case .roku: "Roku"; case .web: "TV" } }
}

/// The big choice on each TV: Mix (recommended), Leaderboard, Par 3 camera, Sponsors, Contests.
struct TVShowTiles: View {
    @Binding var playlist: [PageRef]
    var minWidth: CGFloat = 96
    var body: some View {
        let on = ShowTile.matching(playlist)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minWidth), spacing: 8)], spacing: 8) {
            ForEach(ShowTile.allCases) { t in
                let sel = on == t
                Button { withAnimation(.snappy) { playlist = t.pages } } label: {
                    VStack(spacing: 4) {
                        Image(systemName: t.icon).font(.system(size: 19, weight: .semibold))
                        Text(t.title).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        Text(t.note).font(.system(size: 10)).opacity(0.75).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(sel ? FC.onGreen : FC.ink).frame(maxWidth: .infinity, minHeight: 74)
                    .background(sel ? FC.green : FC.paper2.opacity(0.7), in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(sel ? FC.flag : .clear, lineWidth: 2))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(sel ? .isSelected : [])
            }
        }
    }
}

/// A picture of what the TV shows now (dimmed with OFF when the TV isn't on).
struct TVPicture: View {
    var force: PageRef?
    var playlist: [PageRef]
    var choices: PageChoices
    var online: Bool
    var big = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [FC.green2, FC.green], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: big ? 6 : 2) {
                if let f = force, f.isOn {
                    Image(systemName: PageChoices.icon(f.k)).font(.system(size: big ? 26 : 13, weight: .semibold)).foregroundStyle(FC.flag)
                    Text(choices.label(f)).font(FC.display(big ? 30 : 11)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.6)
                } else {
                    let t = ShowTile.matching(playlist)
                    Image(systemName: t?.icon ?? "rectangle.stack").font(.system(size: big ? 26 : 13, weight: .semibold))
                    Text(t?.title ?? (playlist.isEmpty ? "Everything" : "Own mix")).font(FC.display(big ? 30 : 11)).lineLimit(1).minimumScaleFactor(0.6)
                    if big { Text(normalLine).font(.system(size: 12)).foregroundStyle(FC.onGreenMuted).multilineTextAlignment(.center) }
                }
            }
            .padding(big ? 14 : 4)
            if !online { Color.black.opacity(0.45) }
        }
        .overlay(alignment: .topLeading) {
            Text(online ? "ON" : "OFF").font(.system(size: big ? 10 : 7, weight: .heavy)).tracking(1).foregroundStyle(.white)
                .padding(.horizontal, big ? 7 : 4).padding(.vertical, 2)
                .background(online ? FC.ok : Color.black.opacity(0.6), in: Capsule()).padding(big ? 10 : 3)
                .opacity(big || !online ? 1 : 0)
        }
        .foregroundStyle(FC.onGreen)
        .clipShape(RoundedRectangle(cornerRadius: big ? 14 : 7))
        .accessibilityElement(children: .combine)
    }
    private var normalLine: String {
        playlist.count > 1 ? playlist.map { choices.label($0) }.joined(separator: ", then ") : ""
    }
}

/// One line in the TV list: a small picture, the name, where it is and what it shows, and a dot when it's on.
struct TVRow: View {
    var display: Display
    var online: Int
    var force: PageRef?
    var choices: PageChoices
    var selected = false
    var body: some View {
        HStack(spacing: 11) {
            TVPicture(force: force, playlist: display.playlist, choices: choices, online: online > 0).frame(width: 60, height: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(display.name.isEmpty ? "TV" : display.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(FC.ink).lineLimit(1)
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(line).font(.system(size: 12)).foregroundStyle(FC.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Circle().fill(online > 0 ? FC.ok : FC.line).frame(width: 8, height: 8).accessibilityLabel(online > 0 ? "On" : "Off")
        }
        .padding(.horizontal, 12).padding(.vertical, 8).frame(minHeight: 54)
        .background(selected ? FC.paper2 : .clear)
        .overlay(alignment: .leading) { if selected { Rectangle().fill(FC.green).frame(width: 3) } }
        .contentShape(Rectangle())
    }
    private var line: String {
        let what: String
        if online == 0 { what = "Off · set it up" }
        else if let f = force, f.isOn {
            let m = f.until > 0 ? max(1, Int((f.until / 1000 - Date().timeIntervalSince1970) / 60 + 0.5)) : 0
            what = choices.label(f) + (m > 0 ? ", \(m) more min" : "")
        } else { what = ShowTile.matching(display.playlist)?.title ?? (display.playlist.isEmpty ? "Everything" : "Own mix") }
        return [display.place, what].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// How to put Flagcast on a TV with its link (a TV whose browser can't show a code to type).
struct TVLinkSteps: View {
    var url: URL
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            step(1, "Send yourself the TV’s link", "Email or text it to yourself so you can open it on the TV.")
            HStack(spacing: 8) {
                ShareLink(item: url) { Label("Send the Link", systemImage: "square.and.arrow.up") }.buttonStyle(GreenButton())
                Button { copy(url.absoluteString); copied = true } label: { Label(copied ? "Copied" : "Copy", systemImage: "doc.on.doc") }.buttonStyle(PlainCardButton())
            }
            .padding(.leading, 46)
            step(2, "Open it in the TV’s web browser", "Or on the computer or stick plugged into the TV.")
            step(3, "Make it full screen", "The TV’s dot turns green when it shows Flagcast.")
        }
    }
    private func step(_ n: Int, _ t: String, _ sub: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(FC.display(20)).foregroundStyle(FC.onGreen).frame(width: 34, height: 34).background(FC.green, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(t).font(.system(size: 15, weight: .semibold)).foregroundStyle(FC.ink)
                Text(sub).font(.system(size: 13)).foregroundStyle(FC.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Add a TV, in three steps: what's on the TV, the code it shows (or its link), then its name, where it is and what it
/// shows. A TV connected with a code is one of the club's TVs (every tournament); it's live from step 2 and step 3 saves
/// as it goes, so there's no Save. done(id) gets the new TV (nil when it was cancelled before one was made).
struct AddTVFlow: View {
    let doc: DeskDoc
    let tvs: ClubTVs
    var done: (String?) -> Void

    private enum Step { case kind, code, link, name }
    @State private var step = Step.kind
    @State private var kind = TVKind.appletv
    @State private var code = ""
    @State private var busy = false
    @State private var err: String?
    @State private var tvID: String?
    @State private var club = false
    @State private var name = ""
    @State private var place = ""
    @State private var playlist = ShowTile.mix.pages
    @State private var newPlace = ""
    @State private var addingPlace = false
    @FocusState private var codeFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                switch step {
                case .kind: Button("Cancel") { done(nil) }
                case .code: Button { step = .kind; code = ""; err = nil } label: { Label("Back", systemImage: "chevron.left") }
                default: Color.clear.frame(width: 1, height: 1)
                }
                Spacer()
                Text("Add a TV").font(.system(size: 16, weight: .semibold)).foregroundStyle(FC.ink)
                Spacer()
                if step == .name { Button("Done") { Task { await finish(another: false) } }.fontWeight(.semibold).disabled(busy) }
                else if step == .link { Button("Next") { step = .name }.fontWeight(.semibold) }
                else { Color.clear.frame(width: 50, height: 1) }
            }
            .buttonStyle(.borderless).tint(FC.link).padding(.bottom, 12)
            HStack(spacing: 5) {
                ForEach(0..<3) { i in Capsule().fill(i <= stepIndex ? FC.green : FC.line).frame(height: 4) }
            }
            .padding(.bottom, 18)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch step {
                    case .kind: kindStep
                    case .code: codeStep
                    case .link: linkStep
                    case .name: nameStep
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 20)
            }
        }
        .padding(20)
        .background(FC.paper)
    }
    private var stepIndex: Int { switch step { case .kind: 0; case .code, .link: 1; case .name: 2 } }

    private func heading(_ t: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t).font(FC.display(28)).foregroundStyle(FC.ink)
            Text(sub).font(.system(size: 14)).foregroundStyle(FC.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    // 1. what's on the TV
    @ViewBuilder private var kindStep: some View {
        heading("What’s on the TV?", "Pick one. We’ll show you how to put Flagcast on it.")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 9)], spacing: 9) {
            ForEach(TVKind.allCases) { k in
                Button { kind = k; step = .code } label: {
                    VStack(spacing: 6) {
                        Image(systemName: k.icon).font(.system(size: 26, weight: .semibold)).frame(height: 30)
                        Text(k.title).font(.system(size: 14, weight: .semibold)).multilineTextAlignment(.center)
                        Text(k.getIt).font(.system(size: 11)).foregroundStyle(FC.muted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(FC.ink).padding(12).frame(maxWidth: .infinity, minHeight: 116)
                    .background(FC.card, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(FC.line))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        Button { Task { await makeLinkTV() } } label: { Text("No way to type a code? Send a link instead").font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity) }
            .buttonStyle(.borderless).tint(FC.link).padding(.top, 6).disabled(busy)
    }

    // 2. the code on the TV
    @ViewBuilder private var codeStep: some View {
        heading("Type the code on the TV", kind.open)
        VStack(spacing: 4) {
            Text("flagcast.app/tv").font(.system(size: 10)).foregroundStyle(FC.onGreenMuted)
            Text("K7PMR4").font(.system(size: 24, weight: .bold, design: .monospaced)).tracking(4).foregroundStyle(FC.flag)
        }
        .frame(width: 210, height: 112).background(FC.green, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(white: 0.13), lineWidth: 6))
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
        ZStack {
            TextField("Code", text: $code)
                .focused($codeFocused).autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.characters).keyboardType(.asciiCapable)
                #endif
                .opacity(0.02).frame(width: 300, height: 56)
                .accessibilityLabel("The code on the TV")
            HStack(spacing: 7) {
                ForEach(0..<6, id: \.self) { i in
                    let ch = i < code.count ? String(code[code.index(code.startIndex, offsetBy: i)]) : ""
                    Text(ch).font(.system(size: 28, weight: .bold, design: .monospaced)).foregroundStyle(FC.ink)
                        .frame(width: 42, height: 54)
                        .background(FC.card, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(i < code.count || (i == code.count && codeFocused) ? FC.green : FC.line, lineWidth: i == code.count && codeFocused ? 2.5 : 1.5))
                }
            }
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { codeFocused = true }
        .onAppear { codeFocused = true }
        .onChange(of: code) { _, v in
            let c = String(v.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
            if c != v { code = c; return }
            if c.count == 6 { err = nil; Task { await connect() } }
        }
        if busy { HStack { Spacer(); ProgressView(); Text("Connecting…").foregroundStyle(FC.muted); Spacer() } }
        if let err { Text(err).font(.system(size: 14, weight: .semibold)).foregroundStyle(FC.red).frame(maxWidth: .infinity) }
        if kind != .web {
            Text("No Flagcast TV app on it yet? Open flagcast.app/tv in the TV’s web browser instead: it shows a code too.").font(.system(size: 12)).foregroundStyle(FC.muted).frame(maxWidth: .infinity).multilineTextAlignment(.center)
        }
    }

    // 2b. a TV that shows its link
    @ViewBuilder private var linkStep: some View {
        heading("Put Flagcast on the TV", "Use this when you can’t type a code on the TV. It shows this tournament only.")
        if let tvID { TVLinkSteps(url: doc.tvURL(tvID)) }
        Button { step = .name } label: { Text("Next").frame(maxWidth: .infinity) }.buttonStyle(GreenButton()).padding(.top, 8)
    }

    // 3. name, where, what it shows
    @ViewBuilder private var nameStep: some View {
        if club {
            Label("Connected", systemImage: "checkmark").font(FC.display(28)).foregroundStyle(FC.ok)
            Text("It’s showing \(doc.ev.name.isEmpty ? "this tournament" : doc.ev.name) now, and each new tournament by itself.")
                .font(.system(size: 14)).foregroundStyle(FC.muted).fixedSize(horizontal: false, vertical: true)
        } else {
            heading("Name it", "Then pick where it is and what it shows.")
        }
        VStack(alignment: .leading, spacing: 3) {
            Text("Name").font(.system(size: 11)).foregroundStyle(FC.muted)
            TextField("Bar TV", text: $name).font(.system(size: 16)).textFieldStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 9).background(FC.card, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(FC.line))
        Text("Where is it?").font(.system(size: 13, weight: .bold)).foregroundStyle(FC.ink)
        ChipFlow(items: doc.tvPlaces + (place.isEmpty || doc.tvPlaces.contains(place) ? [] : [place]), selected: place) { p in place = place == p ? "" : p } other: { addingPlace = true }
        Text("What should it show?").font(.system(size: 13, weight: .bold)).foregroundStyle(FC.ink)
        TVShowTiles(playlist: $playlist)
        Button { Task { await finish(another: false) } } label: { Text("Done").frame(maxWidth: .infinity) }.buttonStyle(GreenButton()).disabled(busy).padding(.top, 6)
        Button { Task { await finish(another: true) } } label: { Text("Add Another TV").frame(maxWidth: .infinity) }.buttonStyle(.borderless).tint(FC.link).disabled(busy)
            .alert("Where is it?", isPresented: $addingPlace) {
                TextField("Halfway House", text: $newPlace)
                Button("Add") { let p = newPlace.trimmingCharacters(in: .whitespaces); if !p.isEmpty { place = p }; newPlace = "" }
                Button("Cancel", role: .cancel) { newPlace = "" }
            }
    }

    private func connect() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            let t = try await tvs.add(doc, code: code, name: kind.defaultName, place: "")
            tvID = t.id; club = true; name = t.name; place = t.where
            if let d = doc.ev.displays.first(where: { $0.id == t.id }), !d.playlist.isEmpty { playlist = d.playlist }
            step = .name
        } catch {
            err = (error as? APIError)?.message ?? "That code didn’t work. Check it and try again."
            code = ""
        }
    }
    private func makeLinkTV() async {
        busy = true; defer { busy = false }
        let d = Display(name: "TV \(doc.ev.displays.count + 1)", playlist: ShowTile.mix.pages)
        if await doc.saveTV(d) { tvID = d.id; club = false; name = d.name; step = .link }
    }
    private func finish(another: Bool) async {
        guard let tvID else { done(nil); return }
        busy = true; defer { busy = false }
        let nm = name.trimmingCharacters(in: .whitespaces).isEmpty ? (club ? kind.defaultName : "TV") : name.trimmingCharacters(in: .whitespaces)
        var d = doc.ev.displays.first { $0.id == tvID } ?? Display(id: tvID, name: nm, playlist: playlist)
        if club, d.name != nm || d.place != place { await tvs.edit(doc, tvID, name: nm, place: place) }
        d.name = nm; d.place = place; d.group = place; d.playlist = playlist; d.tv = club
        await doc.saveTV(d)
        doc.flash("\(nm) is set up.")
        if another { reset() } else { done(tvID) }
    }
    private func reset() { step = .kind; code = ""; err = nil; tvID = nil; club = false; name = ""; place = ""; playlist = ShowTile.mix.pages }
}

/// Chips that wrap onto more lines, with "+ Other" at the end.
struct ChipFlow: View {
    var items: [String]
    var selected: String
    var pick: (String) -> Void
    var other: () -> Void
    var body: some View {
        ChipLayout(spacing: 6) {
            ForEach(items, id: \.self) { p in
                let on = selected.caseInsensitiveCompare(p) == .orderedSame
                Button { pick(p) } label: {
                    Text(p).font(.system(size: 13, weight: on ? .semibold : .regular)).padding(.horizontal, 11).padding(.vertical, 6)
                        .foregroundStyle(on ? FC.onGreen : FC.ink)
                        .background(on ? FC.green : FC.card, in: Capsule()).overlay(Capsule().stroke(on ? FC.green : FC.line))
                }
                .buttonStyle(.plain)
            }
            Button(action: other) {
                Label("Other", systemImage: "plus").font(.system(size: 13)).padding(.horizontal, 11).padding(.vertical, 6)
                    .foregroundStyle(FC.link).background(FC.card, in: Capsule()).overlay(Capsule().stroke(FC.line))
            }
            .buttonStyle(.plain)
        }
    }
}

/// Lays its children out left to right, starting a new line when one is full.
struct ChipLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > 0 && x + z.width > w { y += row + spacing; x = 0; row = 0 }
            x += z.width + spacing; row = max(row, z.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, row: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > b.minX && x + z.width > b.maxX { y += row + spacing; x = b.minX; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(z))
            x += z.width + spacing; row = max(row, z.height)
        }
    }
}

/// One TV's page: what it shows now (and something else for a bit), what it shows normally, and the rarely used parts
/// (where it is, always show this tournament, its link, remove). Everything saves at once.
struct TVDetail: View {
    @Bindable var doc: DeskDoc
    let tvs: ClubTVs
    let id: String
    var onRemoved: () -> Void = {}

    @State private var sending = false
    @State private var customize = false
    @State private var setup = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var removing = false
    @State private var pending: Task<Void, Never>?

    private var index: Int? { doc.ev.displays.firstIndex { $0.id == id } }
    private var online: Int { doc.live?.online[id] ?? 0 }
    private var force: PageRef? { doc.live?.live.force[id] }
    private var club: ClubTV? { tvs.tv(id) }

    var body: some View {
        if let i = index {
            let d = doc.ev.displays[i]
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.name.isEmpty ? "TV" : d.name).font(FC.display(30)).foregroundStyle(FC.ink)
                    Text([d.place, club?.kindName ?? (d.tv ? "" : "TV browser, with its link"), online > 0 ? "on" : "off"].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 13)).foregroundStyle(FC.muted)
                }
                TVPicture(force: force, playlist: d.playlist, choices: doc.pageChoices, online: online > 0, big: true)
                    .frame(maxWidth: .infinity).frame(height: 170)
                TimelineView(.periodic(from: .now, by: 15)) { _ in
                    Text(online > 0 ? screenStatus(force, playlist: d.playlist, choices: doc.pageChoices)
                                    : d.tv ? "This TV is off. Turn it on and open Flagcast TV; it comes back by itself." : "This TV isn’t showing Flagcast yet.")
                        .font(.system(size: 13)).foregroundStyle(FC.muted).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    if force?.isOn == true {
                        Button { sendToTVs(doc, id, nil, 0, to: name(d)) } label: { Text("Back to Normal").frame(maxWidth: .infinity) }.buttonStyle(PlainCardButton())
                    }
                    Button { sending = true } label: { Text("Show Something Else…").frame(maxWidth: .infinity) }.buttonStyle(GreenButton())
                    #if os(macOS)
                        .popover(isPresented: $sending, arrowEdge: .bottom) { SendNowPanel(target: name(d), choices: doc.pageChoices) { sendToTVs(doc, id, $0, $1, to: name(d)) } }
                    #endif
                }
                if online == 0 && !d.tv {
                    Button { setup = true } label: { Label("Set Up This TV", systemImage: "tv.badge.wifi").frame(maxWidth: .infinity) }.buttonStyle(PlainCardButton())
                }
                Text("Normally shows").font(.system(size: 13, weight: .bold)).foregroundStyle(FC.ink).padding(.top, 4)
                TVShowTiles(playlist: Binding(get: { doc.ev.displays[safe: id]?.playlist ?? [] }, set: { v in change { $0.playlist = v } }))
                DisclosureGroup(isExpanded: $customize) {
                    customizer
                } label: { Text("Customize…").font(.system(size: 14, weight: .semibold)).foregroundStyle(FC.link) }
                VStack(spacing: 0) {
                    row {
                        Text("Where is it?").font(.system(size: 14, weight: .semibold)).foregroundStyle(FC.ink)
                        Spacer()
                        Menu {
                            ForEach(doc.tvPlaces, id: \.self) { p in Button(p) { setPlace(p) } }
                            if !d.place.isEmpty { Divider(); Button("Not set", role: .destructive) { setPlace("") } }
                        } label: { Text(d.place.isEmpty ? "Pick a place" : d.place).font(.system(size: 14)) }
                        .fixedSize().tint(FC.link)
                    }
                    row {
                        Text("Name").font(.system(size: 14, weight: .semibold)).foregroundStyle(FC.ink)
                        Spacer()
                        Button("Rename…") { newName = d.name; renaming = true }.buttonStyle(.borderless).tint(FC.link)
                    }
                    if let c = club {
                        row {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Always show this tournament").font(.system(size: 14, weight: .semibold)).foregroundStyle(FC.ink)
                                Text(pinNote(c)).font(.system(size: 12)).foregroundStyle(FC.muted)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(get: { c.event == doc.id }, set: { on in Task { await tvs.pin(doc, c, on) } })).labelsHidden().toggleStyle(.switch).tint(FC.ok)
                        }
                    }
                    if !d.tv {
                        row {
                            Text("This TV’s link").font(.system(size: 14, weight: .semibold)).foregroundStyle(FC.ink)
                            Spacer()
                            ShareLink(item: doc.tvURL(id)) { Image(systemName: "square.and.arrow.up") }.buttonStyle(.borderless).tint(FC.link)
                            Button { copy(doc.tvURL(id).absoluteString); doc.flash("Link copied.") } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless).tint(FC.link)
                        }
                    }
                    row(last: true) {
                        Button(role: .destructive) { removing = true } label: { Text("Remove This TV").font(.system(size: 14, weight: .semibold)) }.buttonStyle(.borderless).tint(FC.red)
                        Spacer()
                    }
                }
                .background(FC.card, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(FC.line))
            }
            #if os(iOS)
            .sheet(isPresented: $sending) {
                SendSheet(target: name(d), choices: doc.pageChoices, places: []) { page, mins, _ in sendToTVs(doc, id, page, mins, to: name(d)) }
            }
            #endif
            .sheet(isPresented: $setup) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Put Flagcast on \(name(d))").font(FC.display(28)).foregroundStyle(FC.ink)
                    TVLinkSteps(url: doc.tvURL(id))
                    HStack { Spacer(); Button("Done") { setup = false }.buttonStyle(GreenButton()) }
                }
                .padding(24).frame(minWidth: 360, idealWidth: 480).background(FC.paper)
            }
            .alert("Rename this TV", isPresented: $renaming) {
                TextField("Name", text: $newName)
                Button("Rename") { rename(newName) }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Remove \(name(d))?", isPresented: $removing, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { Task { await remove(d) } }
            } message: { Text(d.tv ? "It’s taken off every tournament and goes back to showing a code." : "It stops showing this tournament.") }
            .onDisappear { pending?.cancel(); if pending != nil, let d = doc.ev.displays[safe: id] { Task { await doc.saveTV(d) } } }
        } else {
            Text("This TV was removed.").foregroundStyle(FC.muted).frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    @ViewBuilder private var customizer: some View {
        let list = Binding(get: { doc.ev.displays[safe: id]?.playlist ?? [] }, set: { v in change { $0.playlist = v } })
        let others = doc.ev.displays.filter { $0.id != id }.map { ($0.id, $0.name) }
        #if os(macOS)
        PlaylistEditor(playlist: list, choices: doc.pageChoices, others: others, copyTo: copyTo).padding(.top, 6)
        #else
        PlaylistList(playlist: list, choices: doc.pageChoices, others: others, copyTo: copyTo)
        #endif
    }

    private func row<C: View>(last: Bool = false, @ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 10) { c() }.padding(.horizontal, 14).frame(minHeight: 48)
            .overlay(alignment: .bottom) { if !last { Rectangle().fill(FC.line.opacity(0.6)).frame(height: 1).padding(.leading, 14) } }
    }
    private func name(_ d: Display) -> String { d.name.isEmpty ? "this TV" : d.name }
    private func pinNote(_ c: ClubTV) -> String {
        c.event.isEmpty ? "Off: shows the tournament of the day" : c.event == doc.id ? "On: shows this tournament on every day" : "Shows \(c.eventName.isEmpty ? "another tournament" : c.eventName) now"
    }
    /// change it here at once, and save it a moment later (taps and typing in a row become one save)
    private func change(_ f: (inout Display) -> Void) {
        guard let i = index else { return }
        f(&doc.ev.displays[i])
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            if Task.isCancelled { return }
            pending = nil
            if let d = doc.ev.displays[safe: id] { await doc.saveTV(d) }
        }
    }
    private func setPlace(_ p: String) {
        if let c = club { Task { await tvs.edit(doc, c.id, name: c.name, place: p); change { $0.place = p; $0.group = p } } }
        else { change { $0.place = p; $0.group = p } }
    }
    private func rename(_ n: String) {
        let n = n.trimmingCharacters(in: .whitespaces); guard !n.isEmpty else { return }
        if let c = club { Task { await tvs.edit(doc, c.id, name: n, place: c.where); change { $0.name = n } } }
        else { change { $0.name = n } }
    }
    private func copyTo(_ ids: [String]) {
        guard let list = doc.ev.displays[safe: id]?.playlist else { return }
        for i in doc.ev.displays.indices where ids.contains(doc.ev.displays[i].id) {
            doc.ev.displays[i].playlist = list
            let d = doc.ev.displays[i]; Task { await doc.saveTV(d) }
        }
        doc.flash("Copied to \(ids.count == 1 ? "that TV" : "\(ids.count) TVs").")
    }
    private func remove(_ d: Display) async {
        pending?.cancel(); pending = nil
        if d.tv, let c = club { await tvs.remove(doc, c) }
        else if d.tv { doc.flash("Couldn’t find this TV in the club’s list. Try again in a moment."); return }
        else if !(await doc.removeTV(id)) { return }
        onRemoved()
    }
}

extension Array where Element == Display {
    subscript(safe id: String) -> Display? { first { $0.id == id } }
}

/// The TV list with Add a TV at the end; tap a TV to open it.
struct TVList<Row: View>: View {
    @Bindable var doc: DeskDoc
    var add: () -> Void
    @ViewBuilder var row: (Display) -> Row
    var body: some View {
        VStack(spacing: 0) {
            ForEach(doc.ev.displays) { d in
                row(d)
                Rectangle().fill(FC.line.opacity(0.6)).frame(height: 1).padding(.leading, 12)
            }
            Button(action: add) {
                Label("Add a TV", systemImage: "plus").font(.system(size: 15, weight: .semibold)).foregroundStyle(FC.link)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading).padding(.horizontal, 14).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(FC.card, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(FC.line))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
