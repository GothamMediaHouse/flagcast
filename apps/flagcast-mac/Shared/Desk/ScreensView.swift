import SwiftUI
import UniformTypeIdentifiers

let SPOT_NAMES: [(String, String)] = [("title", "Title sponsor (every screen)"), ("leaderboard", "Leaderboard sponsor"), ("hole", "Hole sponsor"),
                                     ("cam", "Par 3 camera sponsor"), ("contest", "Contest sponsor"), ("turn", "At the turn"),
                                     ("ace", "Hole in one sponsor"), ("slide", "Own slide on the screens")]

struct ReplayDraft { var hole = 0; var label = ""; var url = "" }

/// Screens and sponsors: the TVs (a list beside the picked TV, saved as they change), then a tab each for sponsors, the
/// announcement, par 3 cameras and replays, fundraising and how the TVs look (those save with Save).
struct ScreensView: View {
    @Bindable var doc: DeskDoc
    @State private var flash = ""
    @State private var raised = ""
    @State private var replay = ReplayDraft()
    @AppStorage("screens.tab") private var tab = "tvs"
    @Environment(DeskNav.self) private var nav

    private static let tabs: [(String, String)] = [("TVs", "tvs"), ("Sponsors", "sponsors"), ("Announcement", "announcement"), ("Cameras & replays", "cameras"),
                                                   ("Fundraising", "fund"), ("How the TVs look", "look")]
    private var shownTab: String { Self.tabs.contains { $0.1 == tab } ? tab : "tvs" }

    var body: some View {
        DeskPage(doc: doc, section: .screens) {
            PhotoSegments(options: Self.tabs, selection: Binding(get: { shownTab }, set: { tab = $0 }))
            Button("Open the board") { NSWorkspace.shared.open(doc.boardURL) }.buttonStyle(GlassButton())
        } title: {
            HeroTitle(title: "Screens & sponsors", size: 52, sub: doc.ev.displays.isEmpty ? "No TVs yet" : "\(doc.tvsOn) of \(doc.ev.displays.count) TVs on", subBeside: true)
        } content: {
            if shownTab == "tvs" { TVWall(doc: doc) }
            else { CardForm { settings } }
        }
    }

    @ViewBuilder private var settings: some View {
        switch shownTab {
        case "sponsors":
            SwiftUI.Section {
                ForEach($doc.ev.sponsors) { $s in SponsorRow(sponsor: $s, holes: doc.ev.course.holes, doc: doc) { doc.ev.sponsors.removeAll { $0.id == s.id } } }
                Button { doc.ev.sponsors.append(Sponsor(id: Ids.make(), name: "")) } label: { Label("Add Sponsor", systemImage: "plus") }
            } header: { Text("Sponsors") } footer: {
                Help("Pick where each sponsor shows. Hole, camera and contest spots use the hole numbers. The link and offer show on the players’ phones, and taps are counted for the report. Logos: PNG or JPG under 140 KB.")
            }
        case "announcement":
            SwiftUI.Section {
                HStack {
                    TextField("Announcement", text: $flash, prompt: Text("Shotgun start in 10 minutes"))
                    Button("Show on Every Screen Now") { Task { if await doc.day("flash", ["text": flash], done: "On every screen now.") != nil { flash = "" } } }.disabled(flash.isEmpty)
                }
                if let f = doc.live?.flash, !f.text.isEmpty {
                    HStack { Text("Showing: “\(f.text)”").foregroundStyle(.secondary); Spacer(); Button("Clear") { Task { await doc.day("flash", ["text": ""], done: "Cleared.") } } }
                }
            } header: { Text("Announcement") } footer: { Help("Shows across every TV and on golfers’ phones until you clear it.") }
        case "cameras":
            SwiftUI.Section {
                PlayerCameraSwitches(doc: doc)
            } header: { Text("Cameras for players") } footer: {
                Help("Choose which cameras golfers see on the Cameras tab of the app and the live leaderboard. Cameras are set up by Flagcast, and a golf pro can go live from an iPhone. Pick “Par 3 camera” for a TV to show a hole’s camera; a hole without one shows a drawing of the hole.")
            }
            SwiftUI.Section {
                HStack {
                    Picker("Hole", selection: $replay.hole) { Text("Hole").tag(0); ForEach(doc.ev.course.holes.filter { $0.par == 3 || doc.live?.cams[$0.n] != nil }, id: \.n) { Text("Hole \($0.n)").tag($0.n) } }.frame(width: 120)
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
            } header: { Text("Replays") } footer: {
                Help("Save Replay plays the hole’s camera back from 25 seconds before you press it (the camera’s HLS link must keep a recording window). Or paste a clip link (.mp4 or .m3u8). Players see replays on their phones, and groups can save their own shot on camera holes.")
            }
        case "fund":
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
        default:
            SwiftUI.Section {
                TextField("Title on the screens", text: $doc.ev.screens.title, prompt: Text("Uses the tournament name"))
                Stepper("\(doc.ev.screens.seconds) seconds on each page", value: $doc.ev.screens.seconds, in: 5...60)
                Stepper("\(doc.ev.screens.rows) rows on each leaderboard page", value: $doc.ev.screens.rows, in: 5...20)
                Toggle("Show gross skins", isOn: $doc.ev.screens.skins)
                TextField("Ticker along the bottom", text: $doc.ev.screens.ticker, prompt: Text("Lunch is served at the turn. Awards at 3 PM in the tent."), axis: .vertical)
            } header: { Text("How the TVs look") } footer: { Help("For every TV in this tournament. Press Save to put it on them.") }
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
    var doc: DeskDoc? = nil
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
                // a wide picture golfers see with the sponsor (saved at once)
                if let doc {
                    PhotoSpot(doc: doc, slot: "s-\(sponsor.id)", label: "Banner", url: doc.ev.photos.sponsor(sponsor.id), height: 52)
                        .frame(width: 150).help("A wide picture golfers see with this sponsor on their phones. It saves as soon as you add it.")
                }
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

/// The TVs: Back to normal and Show on every TV (or the TVs in one place) across the top, the list on the left (Add a
/// TV at the end), the picked TV on the right. A TV saves as it changes, so these need no Save.
struct TVWall: View {
    @Bindable var doc: DeskDoc
    @State private var tvs = ClubTVs()
    @State private var picked: String?
    @State private var adding = false

    /// the places the TVs are at (Show on every TV can pick one)
    private var places: [String] {
        var seen: [String] = []
        for d in doc.ev.displays where !d.place.isEmpty && !seen.contains(where: { $0.caseInsensitiveCompare(d.place) == .orderedSame }) { seen.append(d.place) }
        return seen
    }
    private var shown: String? { picked.flatMap { p in doc.ev.displays.contains { $0.id == p } ? p : nil } ?? doc.ev.displays.first?.id }

    var body: some View {
        VStack(spacing: 14) {
            if !doc.ev.displays.isEmpty {
                SendToManyBar(groups: places, choices: doc.pageChoices) { place, page, mins in
                    let ids: Any = place.map { g in doc.ev.displays.filter { $0.place.caseInsensitiveCompare(g) == .orderedSame }.map(\.id) } ?? "*"
                    sendToTVs(doc, ids, page, mins, to: place.map { "the TVs at \($0)" } ?? "every TV")
                }
            }
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TVS AT THE CLUB").font(.system(size: 11, weight: .bold)).tracking(0.6).foregroundStyle(FC.muted).padding(.leading, 4)
                        TVList(doc: doc, add: { adding = true }) { d in
                            Button { picked = d.id } label: {
                                TVRow(display: d, online: doc.live?.online[d.id] ?? 0, force: doc.live?.live.force[d.id], choices: doc.pageChoices, selected: d.id == shown)
                            }
                            .buttonStyle(.plain)
                        }
                        Text("A TV you add once shows every tournament at the club. What it shows is picked for each tournament.")
                            .font(.system(size: 12)).foregroundStyle(FC.muted).padding(.horizontal, 4)
                    }
                    .padding(16)
                }
                .frame(width: 350)
                Rectangle().fill(FC.line).frame(width: 1)
                ScrollView {
                    Group {
                        if let id = shown { TVDetail(doc: doc, tvs: tvs, id: id) { picked = nil }.id(id) }
                        else {
                            VStack(spacing: 12) {
                                Image(systemName: "tv").font(.system(size: 40)).foregroundStyle(FC.muted)
                                Text("No TVs yet").font(FC.display(32))
                                Text("Add each TV at the club once. It shows this tournament, and every one after it.")
                                    .font(.system(size: 14)).foregroundStyle(FC.muted).multilineTextAlignment(.center).frame(maxWidth: 420)
                                Button("Add a TV") { adding = true }.buttonStyle(GreenButton()).controlSize(.large)
                            }
                            .frame(maxWidth: .infinity).padding(.top, 50)
                        }
                    }
                    .padding(22).frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
                }
            }
            .background(FC.paper, in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .raisedCard()
        }
        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 22)
        .task { await tvs.load(doc); while !Task.isCancelled { try? await Task.sleep(for: .seconds(60)); await tvs.load(doc) } }
        .sheet(isPresented: $adding) {
            AddTVFlow(doc: doc, tvs: tvs) { id in adding = false; if let id { picked = id } }.frame(width: 600, height: 640)
        }
    }
}
