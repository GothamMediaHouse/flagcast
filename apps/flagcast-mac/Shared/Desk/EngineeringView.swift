import SwiftUI

// Screens → Engineering (and Admin → Screens & phones): every TV in one dense table with its id, link, connections,
// override and time left, and a routing matrix (TVs × pages) to switch several at once; then scenes, take-overs,
// the phones banner, the announcement, and each TV's page list in full. The simple cards stay the default for club staff.

/// One TV as Engineering sees it.
struct EngTV: Identifiable, Hashable {
    var id: String, name: String, place: String, group: String, online: Int, force: PageRef?, playlist: [PageRef]
}

/// What Engineering reads and how it changes things, for the desk (one tournament) or Admin (any club's).
struct EngSource {
    var tvs: [EngTV]
    var choices: PageChoices
    var url: (String) -> URL?
    var scenes: [(id: String, name: String)]
    var currentScene = ""
    var take: Take?
    var phone: PhoneRoute?
    var announcement: Flash?
    var replays: [(id: String, label: String)] = []
    /// a day change (op "screen", "scene", "take", "flash"), with the line to show when it's done
    var day: (_ op: String, _ body: [String: Any], _ done: String?) async -> Void
    /// the desk can edit each TV's pages and group in place (saved with Save); Admin can't
    var playlist: ((String) -> Binding<[PageRef]>?)? = nil
    var group: ((String) -> Binding<String>?)? = nil
}

/// The routing matrix's columns: "Normal" (its own pages) and each page a TV can be switched to.
private struct EngRoute: Identifiable, Hashable {
    var id: String, title: String, page: PageRef?
    func matches(_ f: PageRef?) -> Bool {
        guard let f, f.isOn else { return page == nil }
        guard let page else { return false }
        return f.k == page.k && f.fl == page.fl && f.hole == page.hole && f.sponsor == page.sponsor
    }
}

func pageDict(_ p: PageRef?) -> Any { p.map { ["k": $0.k, "fl": $0.fl, "hole": $0.hole, "sponsor": $0.sponsor] as [String: Any] } ?? NSNull() }

struct EngineeringView: View {
    var src: EngSource
    @State private var selected: Set<String> = []
    @State private var length: SendLength = .changed
    @State private var sceneName = ""
    @State private var takeText = ""
    @State private var takeSecs = 25
    @State private var phoneText = ""
    @State private var flashText = ""
    @State private var open: Set<String> = []

    private var routes: [EngRoute] {
        var r = [EngRoute(id: "normal", title: "Normal", page: nil), EngRoute(id: "lb", title: "Leaderboard", page: PageRef(k: "lb"))]
        r += src.choices.flights.map { EngRoute(id: "lb-\($0)", title: "LB \($0)", page: PageRef(k: "lb", fl: $0)) }
        r.append(EngRoute(id: "p3", title: "Par 3s", page: PageRef(k: "p3")))
        r += src.choices.p3.map { EngRoute(id: "p3-\($0)", title: "Cam \($0)", page: PageRef(k: "p3", hole: $0)) }
        r += [("contests", "Contests"), ("skins", "Skins"), ("fund", "Fund"), ("sponsors", "Sponsors"), ("schedule", "Schedule")].map { EngRoute(id: $0.0, title: $0.1, page: PageRef(k: $0.0)) }
        r += src.choices.sponsors.map { EngRoute(id: "sp-\($0.id)", title: $0.name, page: PageRef(k: "sponsor", sponsor: $0.id)) }
        return r
    }
    private var allSelected: Bool { !src.tvs.isEmpty && selected.count == src.tvs.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            toolbar
            table
            if src.playlist != nil { details }
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) { takeOver; announcement }.frame(maxWidth: .infinity)
                VStack(spacing: 16) { scenes; phones }.frame(maxWidth: .infinity)
            }
        }
    }

    // ---- toolbar: selection, how long, send to selected ----
    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("ENGINEERING").font(.system(size: 11, weight: .bold)).tracking(1.4).foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 3).background(FC.blue, in: RoundedRectangle(cornerRadius: 4))
            Text(selected.isEmpty ? "Click cells to switch one TV, or tick TVs to switch several." : "\(selected.count) selected").font(.system(size: 13)).foregroundStyle(FC.muted)
            Spacer()
            Picker("", selection: $length) { ForEach(SendLength.allCases) { Text($0 == .changed ? "Until changed" : $0.title.replacingOccurrences(of: "For ", with: "")).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().fixedSize().help("How long a switch lasts before the TV goes back to normal")
            Menu("Send to Selected") { ForEach(routes.filter { $0.page != nil }) { r in Button(r.title) { route(Array(selected), r) } } }
                .fixedSize().disabled(selected.isEmpty)
            Button("Back to Normal") { route(Array(selected), routes[0]) }.buttonStyle(PlainCardButton()).disabled(selected.isEmpty)
            Button("All Back to Normal") { send("*", nil, to: "every TV") }.buttonStyle(PlainCardButton())
        }
        .padding(.horizontal, 14).padding(.vertical, 10).raisedCard()
    }

    // ---- the table ----
    private var table: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    Toggle("", isOn: Binding(get: { allSelected }, set: { selected = $0 ? Set(src.tvs.map(\.id)) : [] })).labelsHidden().toggleStyle(.checkbox).frame(width: 34)
                    head("", 44); head("TV", 140); head("ID", 64); head("PLACE · GROUP", 130); head("SHOWING NOW", 190); head("NORMAL", 150); head("LINK", 64)
                    ForEach(routes) { r in Text(r.title.uppercased()).font(.system(size: 10, weight: .bold)).lineLimit(1).frame(width: 66).help(r.title) }
                }
                .foregroundStyle(FC.onGreen).frame(height: 34).background(FC.green)
                if src.tvs.isEmpty {
                    GridRow { Text("No TVs yet.").foregroundStyle(FC.muted).padding(14).gridCellColumns(8 + routes.count) }
                }
                ForEach(src.tvs) { t in
                    GridRow {
                        Toggle("", isOn: Binding(get: { selected.contains(t.id) }, set: { if $0 { selected.insert(t.id) } else { selected.remove(t.id) } }))
                            .labelsHidden().toggleStyle(.checkbox).frame(width: 34)
                        HStack(spacing: 4) { Circle().fill(t.online > 0 ? FC.ok : FC.muted.opacity(0.4)).frame(width: 8, height: 8); Text("\(t.online)").monospacedDigit().foregroundStyle(FC.muted) }
                            .frame(width: 44, alignment: .leading).help("Browsers showing this TV’s link")
                        Text(t.name.isEmpty ? "TV" : t.name).fontWeight(.semibold).lineLimit(1).frame(width: 140, alignment: .leading)
                        Text(t.id).font(.system(size: 11).monospaced()).foregroundStyle(FC.muted).textSelection(.enabled).frame(width: 64, alignment: .leading)
                        Text([t.place, t.group == t.place ? "" : t.group].filter { !$0.isEmpty }.joined(separator: " · ")).lineLimit(1).foregroundStyle(FC.muted).frame(width: 130, alignment: .leading)
                        TimelineView(.periodic(from: .now, by: 10)) { _ in showing(t) }.frame(width: 190, alignment: .leading)
                        Text(t.playlist.isEmpty ? "Everything" : t.playlist.map { src.choices.label($0) + " \($0.secs)s" }.joined(separator: " → ")).lineLimit(1).foregroundStyle(FC.muted)
                            .frame(width: 150, alignment: .leading).help(t.playlist.map { src.choices.label($0) + " (\($0.secs) s)" }.joined(separator: "\n"))
                        HStack(spacing: 6) {
                            if let u = src.url(t.id) {
                                Button { copy(u.absoluteString) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless).help(u.absoluteString)
                                Button { NSWorkspace.shared.open(u) } label: { Image(systemName: "arrow.up.right.square") }.buttonStyle(.borderless).help("Open")
                            }
                        }
                        .frame(width: 64, alignment: .leading)
                        ForEach(routes) { r in cell(t, r) }
                    }
                    .font(.system(size: 12)).frame(height: 36)
                    .background(selected.contains(t.id) ? FC.paper2.opacity(0.7) : .clear)
                    .overlay(alignment: .bottom) { Rectangle().fill(FC.hairline).frame(height: 1) }
                }
            }
            .padding(.leading, 6)
        }
        .background(FC.card).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FC.line))
    }
    private func head(_ t: String, _ w: CGFloat) -> some View { Text(t).font(.system(size: 10, weight: .bold)).tracking(0.6).frame(width: w, alignment: .leading) }
    @ViewBuilder private func showing(_ t: EngTV) -> some View {
        if let f = t.force, f.isOn {
            VStack(alignment: .leading, spacing: 1) {
                Text(src.choices.label(f)).fontWeight(.semibold).foregroundStyle(FC.red).lineLimit(1)
                Text(f.until > 0 ? "\(max(1, Int((f.until / 1000 - Date().timeIntervalSince1970) / 60 + 0.99))) min left · until \(Date(timeIntervalSince1970: f.until / 1000).formatted(date: .omitted, time: .shortened))" : "override, no end")
                    .font(.system(size: 10)).foregroundStyle(FC.muted)
            }
        } else { Text("Normal").foregroundStyle(FC.muted) }
    }
    private func cell(_ t: EngTV, _ r: EngRoute) -> some View {
        let on = r.matches(t.force)
        return Button { route([t.id], r) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(on ? (r.page == nil ? FC.ok : FC.red) : FC.paper2.opacity(0.5)).frame(width: 52, height: 24)
                if on { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white) }
            }
            .frame(width: 66).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(r.page == nil ? "Back to normal" : "Switch \(t.name) to \(r.title)")
    }

    // ---- each TV's pages, in full (desk) ----
    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle("Each TV’s normal pages")
            ForEach(src.tvs) { t in
                DisclosureGroup(isExpanded: Binding(get: { open.contains(t.id) }, set: { if $0 { open.insert(t.id) } else { open.remove(t.id) } })) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let g = src.group?(t.id) {
                            HStack { Text("Group").foregroundStyle(FC.muted).frame(width: 60, alignment: .leading); TextField("Group", text: g, prompt: Text("Same as the place")).frame(width: 200)
                                Text("Engineering only: a group apart from the place.").font(.caption).foregroundStyle(FC.muted) }
                        }
                        if let p = src.playlist?(t.id) {
                            PlaylistEditor(playlist: p, choices: src.choices, others: src.tvs.filter { $0.id != t.id }.map { ($0.id, $0.name) },
                                           copyTo: { ids in for id in ids { src.playlist?(id)?.wrappedValue = p.wrappedValue } })
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    HStack { Text(t.name.isEmpty ? "TV" : t.name).fontWeight(.semibold); Text(t.id).font(.caption.monospaced()).foregroundStyle(FC.muted)
                        Text("· \(t.playlist.count) page\(t.playlist.count == 1 ? "" : "s"), \(t.playlist.reduce(0) { $0 + $1.secs }) s a loop").font(.caption).foregroundStyle(FC.muted) }
                }
            }
            Text("Changes here are saved with Save.").font(.caption).foregroundStyle(FC.muted)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).raisedCard()
    }

    // ---- take over, announcement, scenes, phones ----
    private var takeOver: some View {
        box("Take over every TV") {
            if let t = src.take { HStack { Text("Now: \(t.kind)\(t.text.map { " · \($0)" } ?? "")").foregroundStyle(FC.red); Spacer(); Button("Clear") { take(["kind": "clear"]) } } }
            HStack {
                TextField("Message", text: $takeText, prompt: Text("Lunch is served at the turn"))
                Stepper("\(takeSecs) s", value: $takeSecs, in: 5...120, step: 5).monospacedDigit().fixedSize()
            }
            HStack {
                Button("Announce") { take(["kind": "msg", "text": takeText, "secs": takeSecs]) }.disabled(takeText.isEmpty)
                Button("Hole in One!") { take(["kind": "ace", "text": takeText, "secs": takeSecs]) }
                if !src.choices.sponsors.isEmpty { Menu("Sponsor Moment") { ForEach(src.choices.sponsors, id: \.id) { s in Button(s.name) { take(["kind": "sponsor", "sponsor": s.id, "secs": takeSecs]) } } }.fixedSize() }
                if !src.replays.isEmpty { Menu("Replay") { ForEach(src.replays, id: \.id) { r in Button(r.label) { take(["kind": "replay", "replay": r.id]) } } }.fixedSize() }
            }
            Text("Clear also puts every TV back to normal.").font(.caption).foregroundStyle(FC.muted)
        }
    }
    private var announcement: some View {
        box("Announcement (top of every TV)") {
            if let f = src.announcement, !f.text.isEmpty { HStack { Text("Showing: “\(f.text)”").foregroundStyle(FC.muted); Spacer(); Button("Clear") { Task { await src.day("flash", ["text": ""], "Cleared.") } } } }
            HStack { TextField("Announcement", text: $flashText, prompt: Text("Shotgun start in 10 minutes"))
                Button("Show") { let t = flashText; Task { await src.day("flash", ["text": t], "On every TV."); flashText = "" } }.disabled(flashText.isEmpty) }
        }
    }
    private var scenes: some View {
        box("Scenes") {
            if src.scenes.isEmpty { Text("Save what every TV shows now, to put it back later.").font(.callout).foregroundStyle(FC.muted) }
            ForEach(src.scenes, id: \.id) { s in
                HStack {
                    Text(s.name).fontWeight(src.currentScene == s.id ? .semibold : .regular)
                    if src.currentScene == s.id { Text("on now").font(.caption).foregroundStyle(FC.ok) }
                    Spacer()
                    Button("Put Back") { Task { await src.day("scene", ["apply": s.id], "Scene on.") } }
                    Button(role: .destructive) { Task { await src.day("scene", ["remove": s.id], "Scene deleted.") } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                }
            }
            HStack { TextField("Name", text: $sceneName, prompt: Text("Lunch"))
                Button("Save Scene") { let n = sceneName; Task { await src.day("scene", ["save": n], "Scene saved."); sceneName = "" } }.disabled(sceneName.isEmpty) }
        }
    }
    private var phones: some View {
        box("Players’ phones banner") {
            if let p = src.phone {
                HStack { Text("Now: \(src.choices.label(PageRef(k: p.k, fl: p.fl, hole: p.hole, sponsor: p.sponsor)))\(p.text.isEmpty ? "" : " · “\(p.text)”")").foregroundStyle(FC.red); Spacer()
                    Button("Clear") { Task { await src.day("screen", ["display": "phones", "page": NSNull()], "Phones cleared.") } } }
            }
            HStack {
                TextField("Line on the banner", text: $phoneText, prompt: Text("Watch the 7th: closest to the pin is close!"))
                Menu("Send to Phones") {
                    ForEach(routes.filter { $0.page != nil }) { r in Button(r.title) { let t = phoneText; Task { await src.day("screen", ["display": "phones", "page": pageDict(r.page), "text": t], "On every player’s phone.") } } }
                }
                .fixedSize()
            }
        }
    }
    private func box<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { CardTitle(title); c() }.padding(16).frame(maxWidth: .infinity, alignment: .leading).raisedCard()
    }

    // ---- sending ----
    private func route(_ ids: [String], _ r: EngRoute) {
        guard !ids.isEmpty else { return }
        let names = ids.count == 1 ? (src.tvs.first { $0.id == ids[0] }?.name ?? "the TV") : "\(ids.count) TVs"
        send(ids.count == 1 ? ids[0] as Any : ids as Any, r.page, to: names)
    }
    private func send(_ display: Any, _ page: PageRef?, to: String) {
        var b: [String: Any] = ["display": display, "page": pageDict(page)]
        if page != nil, length != .changed { b["mins"] = length.rawValue }
        let done = page == nil ? "Back to normal: \(to)." : length == .changed ? "\(to): \(src.choices.label(page!))." : "\(to): \(src.choices.label(page!)) for \(length.rawValue) min."
        Task { await src.day("screen", b, done) }
    }
    private func take(_ b: [String: Any]) {
        Task { await src.day("take", b, b["kind"] as? String == "clear" ? "Back to normal." : "On every TV now.") }
    }
}
