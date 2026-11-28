import SwiftUI
import PhotosUI
import WebKit

// Screens & sponsors besides the TVs: a page each on iPhone ("On the TVs"), a tab each on a wide iPad.
// The board as it is now, the announcement, sponsors, the big screens, par 3 cameras and replays, and fundraising.
// Everything here is the Mac's: the same tournament fields (saved with Save) and the same day-of calls.

/// Where a sponsor shows (the Mac's list).
let SPONSOR_SPOTS: [(String, String)] = [("title", "Title sponsor (every screen)"), ("leaderboard", "Leaderboard sponsor"), ("hole", "Hole sponsor"),
                                         ("cam", "Par 3 camera sponsor"), ("contest", "Contest sponsor"), ("turn", "At the turn"),
                                         ("ace", "Hole in one sponsor"), ("slide", "Own slide on the screens")]
func sponsorSpotName(_ k: String) -> String { SPONSOR_SPOTS.first { $0.0 == k }?.1 ?? "Own slide on the screens" }

/// The parts of Screens besides the TVs, each on its own page (iPhone) or tab (iPad).
enum ScreensPart: String, CaseIterable, Identifiable {
    case sponsors, announcement, cameras, fund, look
    var id: String { rawValue }
    var title: String { switch self { case .sponsors: "Sponsors"; case .announcement: "Announcement"; case .cameras: "Cameras & replays"; case .fund: "Fundraising"; case .look: "How the TVs look" } }
    var short: String { switch self { case .cameras: "Cameras"; case .look: "Look"; default: title } }
    var icon: String { switch self { case .sponsors: "star.fill"; case .announcement: "megaphone.fill"; case .cameras: "video.fill"; case .fund: "heart.fill"; case .look: "slider.horizontal.3" } }
    var color: Color { switch self { case .sponsors: FC.flag; case .announcement: FC.blue; case .cameras: FC.red; case .fund: FC.ok; case .look: FC.muted } }
    @MainActor @ViewBuilder func view(_ doc: DeskDoc) -> some View {
        switch self {
        case .sponsors: SponsorsCard(doc: doc)
        case .announcement: AnnouncementCard(doc: doc)
        case .cameras: CamerasCard(doc: doc)
        case .fund: FundCard(doc: doc)
        case .look: BoardCard(doc: doc); BigScreensCard(doc: doc)
        }
    }
}

// MARK: - the board, live

/// The board link as it is right now (what a TV shows without its own pages), with the club's logo and colour.
struct BoardCard: View {
    let doc: DeskDoc
    @Environment(\.openURL) private var openURL
    var body: some View {
        CardBox(title: "On the board now", footer: "This is the board link, live. Each TV shows its own pages: pick them on the TV’s page.") {
            VStack(alignment: .leading, spacing: 12) {
                BoardPreview(url: doc.boardURL, brand: doc.live?.brand, club: doc.ev.club)
                HStack(spacing: 8) {
                    Button { openURL(doc.boardURL) } label: { Label("Open the Board", systemImage: "arrow.up.right.square") }.buttonStyle(PlainCardButton(full: true))
                    ShareLink(item: doc.boardURL) { Label("Send the Link", systemImage: "square.and.arrow.up") }.buttonStyle(PlainCardButton(full: true))
                }
            }
            .padding(14)
        }
    }
}

/// A small, live copy of the board. Until it loads: the club's colour and logo (never Flagcast's).
struct BoardPreview: View {
    let url: URL
    var brand: Brand?
    var club = ""
    @State private var loaded = false

    private var accent: Color { brand.flatMap { Color(hex: $0.accent) } ?? FC.green }
    var body: some View {
        ZStack {
            LinearGradient(colors: [accent, accent.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if !loaded {
                VStack(spacing: 8) {
                    if let l = logoURL(brand?.logo) { RemoteLogo(url: l).frame(maxWidth: 160, maxHeight: 60) }
                    else if !(brand?.club ?? club).isEmpty { Text(brand?.club.isEmpty == false ? brand!.club : club).font(FC.display(24)).foregroundStyle(.white) }
                    ProgressView().tint(.white)
                }
            }
            BoardWeb(url: url) { loaded = true }.opacity(loaded ? 1 : 0)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .topTrailing) { if loaded { LiveChip().padding(8) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A live copy of the board")
    }
}

/// The board page in a web view laid out as a 1280-wide TV and shrunk to fit; look only (no taps). It opens the
/// plain board link, not a TV's, so it never counts as one of the club's TVs being on.
private struct BoardWeb: UIViewRepresentable {
    let url: URL
    var onLoad: () -> Void

    final class Web: WKWebView {
        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.width > 0 else { return }
            let z = bounds.width / 1280
            if abs(pageZoom - z) > 0.005 { pageZoom = z }
        }
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var onLoad: () -> Void
        init(_ f: @escaping () -> Void) { onLoad = f }
        func webView(_ w: WKWebView, didFinish _: WKNavigation!) { onLoad() }
    }
    func makeCoordinator() -> Coordinator { Coordinator(onLoad) }
    func makeUIView(context: Context) -> WKWebView {
        let c = WKWebViewConfiguration()
        c.websiteDataStore = .nonPersistent()
        c.allowsInlineMediaPlayback = true
        c.mediaTypesRequiringUserActionForPlayback = .audio
        let w = Web(frame: .zero, configuration: c)
        w.navigationDelegate = context.coordinator
        w.isUserInteractionEnabled = false
        w.scrollView.isScrollEnabled = false
        w.isOpaque = false
        w.backgroundColor = .clear
        w.load(URLRequest(url: url))
        return w
    }
    func updateUIView(_ w: WKWebView, context: Context) {
        context.coordinator.onLoad = onLoad
        if w.url == nil && !w.isLoading { w.load(URLRequest(url: url)) }
    }
}

// MARK: - announcement

struct AnnouncementCard: View {
    let doc: DeskDoc
    @State private var text = ""
    var body: some View {
        CardBox(title: "Announcement", footer: "Shows across every TV and on golfers’ phones until you clear it.") {
            VStack(alignment: .leading, spacing: 10) {
                if let f = doc.live?.flash, !f.text.isEmpty {
                    HStack { Text("Showing: “\(f.text)”").foregroundStyle(FC.muted); Spacer(); Button("Clear") { Task { await doc.day("flash", ["text": ""], done: "Cleared.") } } }
                        .font(.subheadline)
                }
                TextField("Shotgun start in 10 minutes", text: $text, axis: .vertical).padding(10).background(FC.paper2, in: RoundedRectangle(cornerRadius: 9))
                Button("Show on Every TV Now") { let t = text; Task { if await doc.day("flash", ["text": t], done: "On every TV now.") != nil { text = "" } } }
                    .buttonStyle(GreenButton(full: true)).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(14)
        }
    }
}

// MARK: - sponsors

private struct SponsorID: Identifiable { let id: String }

struct SponsorsCard: View {
    @Bindable var doc: DeskDoc
    @State private var editing: SponsorID?
    var body: some View {
        CardBox(title: "Sponsors", footer: "Pick where each sponsor shows. The link and offer show on golfers’ phones, and taps are counted for the report.") {
            if doc.ev.sponsors.isEmpty {
                Text("No sponsors yet. Add the ones you want on the TVs and on golfers’ phones.").font(.subheadline).foregroundStyle(FC.muted).padding(14)
            }
            ForEach(doc.ev.sponsors) { sp in
                Button { editing = SponsorID(id: sp.id) } label: {
                    HStack(spacing: 12) {
                        SponsorLogo(logo: sp.logo, name: sp.name).frame(width: 64, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sp.name.isEmpty ? "New sponsor" : sp.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(FC.ink).lineLimit(1)
                            Text(spotLine(sp)).font(.footnote).foregroundStyle(FC.muted).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Chevron()
                    }
                    .padding(.horizontal, 14).frame(minHeight: 62).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) { Rectangle().fill(FC.hairline).frame(height: 1).padding(.leading, 90) }
            }
            Button {
                let s = Sponsor(id: Ids.make(), name: "")
                doc.ev.sponsors.append(s); editing = SponsorID(id: s.id)
            } label: { Label("Add Sponsor", systemImage: "plus").font(.system(size: 15, weight: .semibold)).foregroundStyle(FC.link) }
            .padding(14)
        }
        .sheet(item: $editing) { e in NavigationStack { SponsorSheet(doc: doc, id: e.id) } }
    }
    private func spotLine(_ s: Sponsor) -> String {
        let spot = sponsorSpotName(s.spot)
        return ["hole", "cam", "contest"].contains(s.spot) && !s.holes.isEmpty ? "\(spot) · hole\(s.holes.count > 1 ? "s" : "") \(s.holes.map(String.init).joined(separator: ", "))" : spot
    }
}

/// A sponsor's logo (a data: picture in the tournament), or its name.
private struct SponsorLogo: View {
    var logo: String
    var name: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(FC.paper2)
            if let img = image { Image(uiImage: img).resizable().scaledToFit().padding(4) }
            else { Text(name.isEmpty ? "Logo" : name).font(.system(size: 10, weight: .bold)).foregroundStyle(FC.muted).lineLimit(2).multilineTextAlignment(.center).padding(3) }
        }
    }
    private var image: UIImage? {
        guard logo.hasPrefix("data:image/"), let comma = logo.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(logo[logo.index(after: comma)...])).flatMap(UIImage.init(data:))
    }
}

/// One sponsor: logo and banner, name, where it shows, the line under the logo, link and offer, the holes.
private struct SponsorSheet: View {
    @Bindable var doc: DeskDoc
    let id: String
    @Environment(\.dismiss) private var dismiss
    @State private var picked: PhotosPickerItem?
    @State private var err: String?
    @State private var confirmRemove = false

    private var index: Int? { doc.ev.sponsors.firstIndex { $0.id == id } }
    private var onServer: Bool { doc.live?.sponsors.contains { $0.id == id } == true }

    var body: some View {
        Group {
            if let i = index { form($doc.ev.sponsors[i]) } else { Text("This sponsor was removed.").foregroundStyle(FC.muted) }
        }
        .background(FC.paper)
        .navigationTitle(index.map { doc.ev.sponsors[$0].name.isEmpty ? "New Sponsor" : doc.ev.sponsors[$0].name } ?? "Sponsor").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    private func form(_ s: Binding<Sponsor>) -> some View {
        let usesHoles = ["hole", "cam", "contest"].contains(s.wrappedValue.spot)
        let holes = doc.ev.course.holes.filter { s.wrappedValue.spot != "cam" || $0.par == 3 }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CardBox(title: "Logo and banner", footer: "The logo shows on the TVs. The banner is a wide picture golfers see with this sponsor on their phones; it saves as soon as you add it.") {
                    HStack(alignment: .top, spacing: 12) {
                        PhotosPicker(selection: $picked, matching: .images) {
                            VStack(spacing: 4) {
                                SponsorLogo(logo: s.wrappedValue.logo, name: "").frame(width: 120, height: 72)
                                Text(s.wrappedValue.logo.isEmpty ? "Add logo" : "Change logo").font(.caption.weight(.semibold)).foregroundStyle(FC.link)
                            }
                        }
                        .buttonStyle(.plain)
                        PhotoSpot(doc: doc, slot: "s-\(id)", label: "Banner", url: doc.ev.photos.sponsor(id), height: 72)
                    }
                    .padding(14)
                    if !s.wrappedValue.logo.isEmpty {
                        Button("Remove Logo", role: .destructive) { s.wrappedValue.logo = "" }.font(.subheadline).padding([.horizontal, .bottom], 14)
                    }
                    if let err { Text(err).font(.footnote).foregroundStyle(FC.red).padding([.horizontal, .bottom], 14) }
                }
                CardBox(title: "Sponsor") {
                    VStack(alignment: .leading, spacing: 12) {
                        BoxField(placeholder: "Sponsor name", text: s.name)
                        Picker("Shows", selection: s.spot) { ForEach(SPONSOR_SPOTS, id: \.0) { Text($0.1).tag($0.0) } }.tint(FC.link)
                        BoxField(placeholder: "Line under the logo (optional)", text: s.line)
                    }
                    .padding(14)
                }
                if usesHoles {
                    CardBox(title: "Which holes", footer: s.wrappedValue.spot == "cam" ? "Only par 3s have a camera." : nil) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], spacing: 6) {
                            ForEach(holes, id: \.n) { h in
                                let on = s.wrappedValue.holes.contains(h.n)
                                Button { s.wrappedValue.holes = on ? s.wrappedValue.holes.filter { $0 != h.n } : (s.wrappedValue.holes + [h.n]).sorted() } label: {
                                    Text("\(h.n)").font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 40)
                                        .foregroundStyle(on ? FC.onGreen : FC.ink)
                                        .background(on ? FC.green : FC.paper2, in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Hole \(h.n)").accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                        .padding(14)
                    }
                }
                CardBox(title: "On golfers’ phones", footer: "Golfers can tap through to the sponsor’s website.") {
                    VStack(alignment: .leading, spacing: 12) {
                        BoxField(placeholder: "Website (https://…)", text: s.url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        BoxField(placeholder: "Offer for golfers (10% off in the pro shop)", text: s.offer)
                    }
                    .padding(14)
                }
                Button { showNow() } label: { Label("Show on Every TV for 5 Minutes", systemImage: "tv") }.buttonStyle(GreenButton(full: true))
                Button("Remove This Sponsor", role: .destructive) { confirmRemove = true }.buttonStyle(PlainCardButton(full: true))
                    .confirmationDialog("Remove this sponsor?", isPresented: $confirmRemove, titleVisibility: .visible) {
                        Button("Remove", role: .destructive) { doc.ev.sponsors.removeAll { $0.id == id }; dismiss() }
                    } message: { Text("It comes off the TVs and golfers’ phones when you press Save.") }
            }
            .padding(16)
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            picked = nil
            Task {
                guard let d = try? await item.loadTransferable(type: Data.self), let uri = SponsorLogoPrep.dataURI(d) else { err = "That picture couldn’t be used. Try another."; return }
                err = nil
                if let i = index { doc.ev.sponsors[i].logo = uri }
            }
        }
    }

    private func showNow() {
        if !onServer { doc.flash("Press Save first, then you can show this sponsor."); return }
        send(doc, "*", PageRef(k: "sponsor", sponsor: id), 5, to: "every TV")
    }
}

/// A sponsor logo as the data: picture the tournament keeps (the server takes them under 140 KB): shrunk until it fits.
enum SponsorLogoPrep {
    static func dataURI(_ data: Data) -> String? {
        guard let img = UIImage(data: data), img.size.width > 0 else { return nil }
        let px = CGSize(width: img.size.width * img.scale, height: img.size.height * img.scale)
        for side in [800.0, 640, 480, 360, 260] {
            let f = min(1, side / max(px.width, px.height))
            let size = CGSize(width: max(1, (px.width * f).rounded()), height: max(1, (px.height * f).rounded()))
            let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = false
            let out = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
            if let png = out.pngData(), png.count < 140_000 { return "data:image/png;base64," + png.base64EncodedString() }
            if let jpg = out.jpegData(compressionQuality: 0.8), jpg.count < 140_000 { return "data:image/jpeg;base64," + jpg.base64EncodedString() }
        }
        return nil
    }
}

// MARK: - the big screens

struct BigScreensCard: View {
    @Bindable var doc: DeskDoc
    var body: some View {
        CardBox(title: "Big screens") {
            VStack(alignment: .leading, spacing: 12) {
                BoxField(placeholder: doc.ev.name.isEmpty ? "Title on the screens" : "Title on the screens (\(doc.ev.name))", text: $doc.ev.screens.title)
                Stepper("\(doc.ev.screens.seconds) seconds on each page", value: $doc.ev.screens.seconds, in: 5...60)
                Stepper("\(doc.ev.screens.rows) rows on each leaderboard page", value: $doc.ev.screens.rows, in: 5...20)
                Toggle("Show gross skins", isOn: $doc.ev.screens.skins).tint(FC.primary)
                TextField("Ticker along the bottom", text: $doc.ev.screens.ticker, prompt: Text("Lunch is served at the turn. Awards at 3 PM in the tent."), axis: .vertical)
                    .padding(12).background(FC.paper2, in: RoundedRectangle(cornerRadius: 10))
            }
            .font(.subheadline)
            .padding(14)
        }
    }
}

// MARK: - par 3 cameras and replays

/// Whether each par 3 has a camera (Flagcast sets them up; the feeds themselves stay with Flagcast staff), and replays.
struct CamerasCard: View {
    let doc: DeskDoc
    @State private var replay = ReplayDraft()
    @State private var goingLive = false
    private var par3s: [Hole] { doc.ev.course.holes.filter { $0.par == 3 } }
    private var phoneLive: [Int: String] { doc.live?.golive ?? [:] }
    /// par 3s, plus any other hole live from a phone now
    private var camHoles: [Hole] { doc.ev.course.holes.filter { $0.par == 3 || phoneLive[$0.n] != nil } }
    // (the clubhouse camera, 0, is listed in Cameras for players)

    var body: some View {
        CardBox(title: "Cameras", footer: "Go live sends this iPhone’s camera to a hole: the club TVs and the players’ Cameras tab show it. Pick “Par 3 camera” for a TV to show a hole’s camera; a hole without one shows a drawing of the hole.") {
            Button { goingLive = true } label: {
                Label("Go live from this iPhone", systemImage: "video.badge.plus").font(.system(size: 15, weight: .semibold)).foregroundStyle(FC.link)
                    .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading).padding(.horizontal, 14)
            }
            .buttonStyle(.plain)
            .overlay(alignment: .bottom) { Rectangle().fill(FC.hairline).frame(height: 1).padding(.leading, 14) }
            .fullScreenCover(isPresented: $goingLive) {
                GoLiveView(model: GoLiveModel(holes: GoLiveHole.from(doc.ev.course.holes)) { [doc] body in
                    var b = body
                    let op = b.removeValue(forKey: "op") as? String ?? ""
                    return try await Net.desk(doc.id, doc.key, op, b)
                }, liveNow: phoneLive)
            }
            if camHoles.isEmpty { Text("This course has no par 3s.").font(.subheadline).foregroundStyle(FC.muted).padding(14) }
            ForEach(camHoles, id: \.n) { h in
                let on = !(doc.live?.cams[h.n] ?? doc.ev.cams[h.n] ?? "").isEmpty
                HStack {
                    Text("Hole \(h.n)").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    if let who = phoneLive[h.n] {
                        Label("Live from \(who)’s phone", systemImage: "dot.radiowaves.left.and.right").font(.subheadline).foregroundStyle(FC.ok)
                    } else {
                        Label(on ? "Camera set up" : "No camera", systemImage: on ? "video.fill" : "video.slash").font(.subheadline).foregroundStyle(on ? FC.ok : FC.muted)
                    }
                }
                .padding(.horizontal, 14).frame(minHeight: 46)
                .overlay(alignment: .bottom) { Rectangle().fill(FC.hairline).frame(height: 1).padding(.leading, 14) }
            }
        }
        CardBox(title: "Cameras for players", footer: "Choose which cameras golfers see on the Cameras tab of the app and the live leaderboard, and whether groups can save their shot (a 15-second replay from the club’s camera).") {
            PlayerCameraSwitches(doc: doc, inset: 14).padding(.vertical, 6).tint(FC.ok)
        }
        if !par3s.isEmpty {
            CardBox(title: "Par 3 replays", footer: "Save Replay keeps the last 25 seconds of the hole’s camera. Or paste a video link. Golfers see replays on their phones too.") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Hole", selection: $replay.hole) { Text("Pick a hole").tag(0); ForEach(doc.ev.course.holes.filter { $0.par == 3 || doc.live?.cams[$0.n] != nil }, id: \.n) { Text("Hole \($0.n)").tag($0.n) } }.tint(FC.link)
                    BoxField(placeholder: "Who and what (Dana Ruiz, 3 feet!)", text: $replay.label)
                    BoxField(placeholder: "Video link (optional)", text: $replay.url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    HStack(spacing: 8) {
                        Button("Save Replay") { save(screens: false) }.buttonStyle(PlainCardButton(full: true))
                        Button("Save and Show") { save(screens: true) }.buttonStyle(GreenButton(full: true))
                    }
                    .disabled(replay.hole == 0)
                }
                .padding(14)
                ForEach(doc.live?.replays ?? doc.ev.replays) { r in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.label.isEmpty ? "Replay" : r.label).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                            Text("Hole \(r.hole) · \(Date(timeIntervalSince1970: r.at / 1000).formatted(date: .omitted, time: .shortened))").font(.footnote).foregroundStyle(FC.muted)
                        }
                        Spacer()
                        Button("Show") { Task { await doc.day("take", ["kind": "replay", "replay": r.id], done: "On every TV now.") } }.buttonStyle(PlainCardButton())
                        Button(role: .destructive) { Task { await doc.day("replay", ["remove": r.id], done: "Removed.") } } label: { Image(systemName: "trash") }
                            .accessibilityLabel("Remove this replay")
                    }
                    .padding(.horizontal, 14).frame(minHeight: 56)
                    .overlay(alignment: .top) { Rectangle().fill(FC.hairline).frame(height: 1) }
                }
            }
        }
    }
    private func save(screens: Bool) {
        Task {
            var b: [String: Any] = ["hole": replay.hole, "label": replay.label, "screens": screens]
            if !replay.url.isEmpty { b["url"] = replay.url }
            if await doc.day("replay", b, done: screens ? "Saved and on the TVs." : "Replay saved.") != nil { replay.label = ""; replay.url = "" }
        }
    }
}

private struct ReplayDraft { var hole = 0; var label = ""; var url = "" }

// MARK: - fundraising

struct FundCard: View {
    @Bindable var doc: DeskDoc
    @State private var raised = ""
    private func money(_ v: Double) -> String { v.formatted(.currency(code: "USD").precision(.fractionLength(0))) }
    var body: some View {
        CardBox(title: "Fundraising") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Show the total on the TVs", isOn: $doc.ev.fund.on).tint(FC.primary)
                BoxField(placeholder: "Heading (Raised for the foundation today)", text: $doc.ev.fund.label)
                HStack {
                    Text("Goal").foregroundStyle(FC.muted)
                    Spacer()
                    TextField("Goal", value: $doc.ev.fund.goal, format: .currency(code: "USD").precision(.fractionLength(0))).keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing).frame(width: 140).padding(8).background(FC.paper2, in: RoundedRectangle(cornerRadius: 8))
                }
                BoxField(placeholder: "Giving link (https://…)", text: $doc.ev.fund.give).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Divider().overlay(FC.hairline)
                (Text("Raised so far: ").foregroundStyle(FC.muted) + Text(money(doc.live?.fund.raised ?? doc.ev.fund.raised)).bold())
                HStack(spacing: 8) {
                    TextField("New total", text: $raised).keyboardType(.decimalPad).padding(10).background(FC.paper2, in: RoundedRectangle(cornerRadius: 9))
                    Button("Update the Total") {
                        guard let n = Double(raised) else { return }
                        Task { if await doc.day("fund", ["raised": n], done: "Total updated on the TVs.") != nil { raised = "" } }
                    }
                    .buttonStyle(GreenButton()).disabled(Double(raised) == nil)
                }
            }
            .font(.subheadline)
            .padding(14)
        }
    }
}
