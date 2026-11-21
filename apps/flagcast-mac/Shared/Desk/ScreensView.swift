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

    private var par3s: [Hole] { doc.ev.course.holes.filter { $0.par == 3 } }

    var body: some View {
        DeskPage(doc: doc, section: .screens) {
            Button("Open the board") { NSWorkspace.shared.open(doc.boardURL) }.buttonStyle(GlassButton())
        } title: {
            HeroTitle(title: "Screens & sponsors", size: 52, sub: "What the big screens show", subBeside: true)
        } content: {
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
