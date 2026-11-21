import SwiftUI
import UniformTypeIdentifiers

let SPOT_NAMES: [(String, String)] = [("title", "Title sponsor (every screen)"), ("leaderboard", "Leaderboard sponsor"), ("hole", "Hole sponsor"),
                                     ("cam", "Par 3 camera sponsor"), ("contest", "Contest sponsor"), ("turn", "At the turn"),
                                     ("ace", "Hole in one sponsor"), ("slide", "Own slide on the screens")]

struct ReplayDraft { var hole = 0; var label = ""; var url = "" }

/// Screens and sponsors: what the big screens show, the announcement, par 3 cameras and replays, sponsors, fundraising.
struct ScreensView: View {
    @Bindable var doc: DeskDoc
    @State private var flash = ""
    @State private var raised = ""
    @State private var replay = ReplayDraft()
    @AppStorage("screens.tab") private var tab = "screens"

    private var par3s: [Hole] { doc.ev.course.holes.filter { $0.par == 3 } }

    var body: some View {
        DeskPage(doc: doc, section: .screens) {
            PhotoSegments(options: [("TVs", "screens"), ("Sponsors & more", "settings")], selection: $tab)
            Button("Open the board") { NSWorkspace.shared.open(doc.boardURL) }.buttonStyle(GlassButton())
        } title: {
            HeroTitle(title: "Screens & sponsors", size: 52, sub: tab == "screens" ? "The TVs at the club and what they show" : "Sponsors, cameras, announcements", subBeside: true)
        } content: {
            if tab == "screens" { ScreenWall(doc: doc) } else { settings }
        }
    }

    private var settings: some View {
            CardForm {
            SwiftUI.Section("Big screens") {
                TextField("Title on the screens", text: $doc.ev.screens.title, prompt: Text("Uses the tournament name"))
                Stepper("\(doc.ev.screens.seconds) seconds on each page", value: $doc.ev.screens.seconds, in: 5...60)
                Stepper("\(doc.ev.screens.rows) rows on each leaderboard page", value: $doc.ev.screens.rows, in: 5...20)
                Toggle("Show gross skins", isOn: $doc.ev.screens.skins)
                TextField("Ticker along the bottom", text: $doc.ev.screens.ticker, prompt: Text("Lunch is served at the turn. Awards at 3 PM in the tent."), axis: .vertical)
            }
            SwiftUI.Section {
                HStack {
                    TextField("Announcement", text: $flash, prompt: Text("Shotgun start in 10 minutes"))
                    Button("Show on Every Screen Now") { Task { if await doc.day("flash", ["text": flash], done: "On every screen now.") != nil { flash = "" } } }.disabled(flash.isEmpty)
                }
                if let f = doc.live?.flash {
                    HStack { Text("Showing: “\(f.text)”").foregroundStyle(.secondary); Spacer(); Button("Clear") { Task { await doc.day("flash", ["text": ""], done: "Cleared.") } } }
                }
            } header: { Text("Announcement") }
            SwiftUI.Section {
                if par3s.isEmpty { Text("This course has no par 3s.").foregroundStyle(.secondary) }
                ForEach(par3s, id: \.n) { h in
                    TextField("Hole \(h.n)", text: Binding(get: { doc.ev.cams[h.n] ?? "" }, set: { doc.ev.cams[h.n] = $0.isEmpty ? nil : $0 }), prompt: Text("https://… (.m3u8 or a web player link)"))
                }
            } header: { Text("Par 3 cameras") } footer: {
                Help("For each par 3, paste the camera’s https link: an HLS stream (.m3u8) or a web player link such as a VDO.Ninja view link. Leave it empty to show a drawing of the hole.")
            }
            SwiftUI.Section {
                HStack {
                    Picker("Hole", selection: $replay.hole) { Text("Hole").tag(0); ForEach(par3s, id: \.n) { Text("Hole \($0.n)").tag($0.n) } }.frame(width: 120)
                    TextField("Who and what", text: $replay.label, prompt: Text("Dana Ruiz, 3 feet!"))
                    TextField("Clip link", text: $replay.url, prompt: Text("Optional"))
                    Button("Save Replay") { saveReplay(screens: false) }.disabled(replay.hole == 0)
                    Button("Save and Show") { saveReplay(screens: true) }.disabled(replay.hole == 0)
                }
                ForEach(doc.live?.replays ?? doc.ev.replays) { r in
                    HStack {
                        Text("Hole \(r.hole)").monospacedDigit().foregroundStyle(.secondary)
                        Text(r.label.isEmpty ? "Replay" : r.label)
                        Text(Date(timeIntervalSince1970: r.at / 1000).formatted(date: .omitted, time: .shortened)).foregroundStyle(.tertiary)
                        Spacer()
                        Button("Show on Screens") { Task { await doc.day("take", ["kind": "replay", "replay": r.id], done: "On every screen now.") } }
                        Button(role: .destructive) { Task { await doc.day("replay", ["remove": r.id], done: "Removed.") } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                }
            } header: { Text("Par 3 replays") } footer: {
                Help("Save Replay plays the hole’s camera back from 25 seconds before you press it (the camera’s HLS link must keep a recording window). Or paste a clip link (.mp4 or .m3u8). Players see replays on their phones.")
            }
            SwiftUI.Section {
                ForEach($doc.ev.sponsors) { $s in SponsorRow(sponsor: $s, holes: doc.ev.course.holes) { doc.ev.sponsors.removeAll { $0.id == s.id } } }
                Button { doc.ev.sponsors.append(Sponsor(id: Ids.make(), name: "")) } label: { Label("Add Sponsor", systemImage: "plus") }
            } header: { Text("Sponsors") } footer: {
                Help("Pick where each sponsor shows. Hole, camera and contest spots use the hole numbers. The link and offer show on the players’ phones, and taps are counted for the report. Logos: PNG or JPG under 140 KB.")
            }
            SwiftUI.Section("Fundraising") {
                Toggle("Show the total on the screens", isOn: $doc.ev.fund.on)
                TextField("Heading", text: $doc.ev.fund.label, prompt: Text("Raised for the foundation today"))
                LabeledContent("Goal") { TextField("", value: $doc.ev.fund.goal, format: .currency(code: "USD").precision(.fractionLength(0))).frame(width: 120).multilineTextAlignment(.trailing) }
                TextField("Giving link (https)", text: $doc.ev.fund.give, prompt: Text("https://"))
                HStack {
                    Text("Raised so far: ") + Text((doc.live?.fund.raised ?? doc.ev.fund.raised).formatted(.currency(code: "USD").precision(.fractionLength(0)))).bold()
                    Spacer()
                    TextField("", text: $raised, prompt: Text("New total")).frame(width: 110)
                    Button("Update the Total") { if let n = Double(raised) { Task { if await doc.day("fund", ["raised": n], done: "Total updated on the screens.") != nil { raised = "" } } } }.disabled(Double(raised) == nil)
                }
            }
            }
    }
    private func saveReplay(screens: Bool) {
        Task {
            var b: [String: Any] = ["hole": replay.hole, "label": replay.label, "screens": screens]
            if !replay.url.isEmpty { b["url"] = replay.url }
            if await doc.day("replay", b, done: screens ? "Saved and on the screens." : "Replay saved.") != nil { replay.label = ""; replay.url = "" }
        }
    }
}

struct SponsorRow: View {
    @Binding var sponsor: Sponsor
    var holes: [Hole]
    var remove: () -> Void
    @State private var importing = false
    @State private var err: String?
    private var usesHoles: Bool { ["hole", "cam", "contest"].contains(sponsor.spot) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Button { importing = true } label: {
                    Group {
                        if let img = logo { Image(nsImage: img).resizable().scaledToFit() }
                        else { VStack(spacing: 2) { Image(systemName: "photo"); Text("Logo").font(.caption2) }.foregroundStyle(.secondary) }
                    }
                    .frame(width: 88, height: 52).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain).help("Choose a logo (PNG or JPG under 140 KB)")
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("Sponsor name", text: $sponsor.name)
                        Picker("", selection: $sponsor.spot) { ForEach(SPOT_NAMES, id: \.0) { Text($0.1).tag($0.0) } }.labelsHidden().frame(width: 230)
                        Button(role: .destructive, action: remove) { Image(systemName: "trash") }.buttonStyle(.borderless).help("Remove this sponsor")
                    }
                    TextField("Line under the logo", text: $sponsor.line, prompt: Text("Optional"))
                    HStack { TextField("Link (https)", text: $sponsor.url, prompt: Text("https://")); TextField("Offer for players", text: $sponsor.offer, prompt: Text("10% off in the pro shop")) }
                    if usesHoles {
                        HStack(spacing: 3) {
                            Text("Holes").foregroundStyle(.secondary)
                            ForEach(holes.filter { sponsor.spot != "cam" || $0.par == 3 }, id: \.n) { h in
                                Toggle("\(h.n)", isOn: Binding(get: { sponsor.holes.contains(h.n) }, set: { on in sponsor.holes = on ? (sponsor.holes + [h.n]).sorted() : sponsor.holes.filter { $0 != h.n } }))
                                    .toggleStyle(.button).controlSize(.small)
                            }
                        }
                    }
                    if let err { Text(err).foregroundStyle(.red).font(.callout) }
                }
            }
        }
        .padding(.vertical, 4)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.png, .jpeg]) { r in
            guard case .success(let url) = r else { return }
            let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
            guard let d = try? Data(contentsOf: url) else { return }
            if d.count > 140_000 { err = "That picture is \(d.count / 1000) KB. Use one under 140 KB."; return }
            err = nil
            sponsor.logo = "data:image/\(url.pathExtension.lowercased() == "png" ? "png" : "jpeg");base64,\(d.base64EncodedString())"
        }
    }
    private var logo: NSImage? {
        guard sponsor.logo.hasPrefix("data:image/"), let comma = sponsor.logo.firstIndex(of: ","), let d = Data(base64Encoded: String(sponsor.logo[sponsor.logo.index(after: comma)...])) else { return nil }
        return NSImage(data: d)
    }
}

// MARK: - the TVs

/// Every TV at the club as a card: its name and where it is, what it shows now (and something else for a bit), and
/// what it shows normally (big picture tiles; the detail is behind Customize).
struct ScreenWall: View {
    @Bindable var doc: DeskDoc
    @State private var custom: Set<String> = []

    static let PLACES = ["Clubhouse", "Bar", "Grill room", "Pro shop", "Tent", "Patio", "Locker room", "Hole 7 tee", "Hole 18 green"]

    private var choices: PageChoices {
        PageChoices(flights: doc.ev.flights, p3: doc.ev.course.holes.filter { $0.par == 3 }.map(\.n), holes: doc.ev.course.holes.map(\.n),
                    sponsors: doc.ev.sponsors.map { ($0.id, $0.name.isEmpty ? "Sponsor" : $0.name) })
    }
    /// the places TVs are at (more than one TV there, or any named place): "All at once" can pick one
    private var places: [String] {
        var seen: [String] = []
        for d in doc.ev.displays where !d.place.isEmpty && !seen.contains(where: { $0.caseInsensitiveCompare(d.place) == .orderedSame }) { seen.append(d.place) }
        return seen
    }
    /// TVs the server knows (saved): only those can be switched
    private var saved: Set<String> { Set((doc.live?.displays ?? []).map(\.id)) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if doc.ev.displays.isEmpty { empty }
                else {
                    if doc.ev.displays.count > 1 {
                        SendToManyBar(groups: places, choices: choices) { place, page, mins in
                            let ids = place.map { g in doc.ev.displays.filter { $0.place.caseInsensitiveCompare(g) == .orderedSame && saved.contains($0.id) }.map(\.id) }
                            send(ids.map { $0 as Any } ?? "*", page, mins, to: place.map { "the TVs at \($0)" } ?? "every TV")
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 500, maximum: 760), spacing: 16, alignment: .top)], spacing: 16) {
                        ForEach($doc.ev.displays) { $d in card($d) }
                    }
                    HStack { Spacer(); Button { addTV() } label: { Label("Add Another TV", systemImage: "plus") }.buttonStyle(PlainCardButton()) }
                }
            }
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 22)
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "tv").font(.system(size: 40)).foregroundStyle(FC.muted)
            Text("No TVs yet").font(FC.display(32))
            Text("Add each TV at the club. You’ll pick what it shows, and we’ll show you how to put Flagcast on it.")
                .font(.system(size: 14)).foregroundStyle(FC.muted).multilineTextAlignment(.center).frame(maxWidth: 420)
            Button("Add Your First TV") { addTV() }.buttonStyle(GreenButton()).controlSize(.large)
        }
        .padding(36).frame(maxWidth: .infinity).raisedCard()
    }

    private func addTV() {
        doc.ev.displays.append(Display(name: "TV \(doc.ev.displays.count + 1)", playlist: ShowTile.mix.pages))
    }

    private func card(_ d: Binding<Display>) -> some View {
        let id = d.wrappedValue.id, isSaved = saved.contains(id)
        let place = Binding<String>(get: { d.wrappedValue.place }, set: { d.wrappedValue.place = $0; d.wrappedValue.group = $0 })   // TVs in one place go together
        return ScreenCard(name: d.wrappedValue.name, online: doc.live?.online[id] ?? 0, force: doc.live?.live.force[id], playlist: d.wrappedValue.playlist,
                          url: URL(string: "\(doc.boardURL.absoluteString)?screen=\(id)"), choices: choices,
                          send: { page, mins in
                              if !isSaved { doc.flash("Press Save first, then you can switch this TV."); return }
                              send(id, page, mins, to: d.wrappedValue.name.isEmpty ? "the TV" : d.wrappedValue.name)
                          }) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("TV name", text: d.name, prompt: Text("Name this TV")).textFieldStyle(.plain).font(FC.display(24))
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 11)).foregroundStyle(FC.muted)
                    TextField("Where is it?", text: place, prompt: Text("Where is it? (optional)")).textFieldStyle(.plain).font(.system(size: 13))
                    Menu { ForEach(Self.PLACES + places.filter { p in !Self.PLACES.contains(p) }, id: \.self) { p in Button(p) { place.wrappedValue = p } } } label: { Image(systemName: "chevron.down") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Pick a place")
                }
            }
        } details: {
            Divider().overlay(FC.hairline)
            Text("What should this TV show?").font(.system(size: 14, weight: .bold))
            ShowTiles(playlist: d.playlist)
            DisclosureGroup(isExpanded: Binding(get: { custom.contains(id) }, set: { if $0 { custom.insert(id) } else { custom.remove(id) } })) {
                PlaylistEditor(playlist: d.playlist, choices: choices,
                               others: doc.ev.displays.filter { $0.id != id }.map { ($0.id, $0.name) },
                               copyTo: { ids in
                                   let list = d.wrappedValue.playlist
                                   for i in doc.ev.displays.indices where ids.contains(doc.ev.displays[i].id) { doc.ev.displays[i].playlist = list }
                                   doc.flash("Copied. Press Save to put it on those TVs.")
                               })
                .padding(.top, 6)
                HStack {
                    Spacer()
                    Button(role: .destructive) { doc.ev.displays.removeAll { $0.id == id } } label: { Label("Remove This TV", systemImage: "trash") }
                        .buttonStyle(.borderless).controlSize(.small)
                }
            } label: { Text("Customize…").font(.system(size: 12, weight: .semibold)).foregroundStyle(FC.link) }
            if !isSaved { Label("New TV: press Save to switch it on.", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(FC.muted) }
        }
    }

    /// display: an id, a list of ids or "*"; page nil = back to normal
    private func send(_ display: Any, _ page: PageRef?, _ mins: Int, to: String) {
        if let ids = display as? [Any], ids.isEmpty { doc.flash("No saved TVs there yet."); return }
        var b: [String: Any] = ["display": display, "page": page.map { ["k": $0.k, "fl": $0.fl, "hole": $0.hole, "sponsor": $0.sponsor] as [String: Any] } ?? NSNull()]
        if page != nil, mins > 0 { b["mins"] = mins }
        let done = page == nil ? "\(to.prefix(1).uppercased() + to.dropFirst()) is back to normal." : mins > 0 ? "On \(to) for \(mins) minutes." : "On \(to) until you switch back."
        Task { await doc.day("screen", b, done: done) }
    }
}
