import SwiftUI

/// Screens: Show on every TV, Back to normal and Go live at the top, then the TVs (one line each: tap one for its page)
/// and the other parts (sponsors, the announcement, cameras and replays, fundraising, how the TVs look), each on its own
/// page. A wide iPad shows them as tabs, with the TV list beside the picked TV. TVs save as they change (no Save).
struct ScreensView: View {
    var body: some View {
        WithTournament { doc in ScreensPage(doc: doc) }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { TournamentMenu() } }
    }
}

private struct PageWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct ScreensPage: View {
    @Bindable var doc: DeskDoc
    @State private var tvs = ClubTVs()
    @State private var width: CGFloat = 0
    @State private var adding = false
    @State private var allSending = false
    @State private var goingLive = false
    @State private var picked: String?
    @AppStorage("screens.part") private var part = "tvs"
    @Environment(\.horizontalSizeClass) private var size
    @Environment(\.openURL) private var openURL

    /// tabs, with the TV list beside the picked TV: iPad landscape, or a big iPad
    private var wide: Bool { size == .regular && width >= 860 }
    /// the places the TVs are at (Show on every TV can pick one)
    private var places: [String] {
        var seen: [String] = []
        for d in doc.ev.displays where !d.place.isEmpty && !seen.contains(where: { $0.caseInsensitiveCompare(d.place) == .orderedSame }) { seen.append(d.place) }
        return seen
    }
    private var kicker: String {
        let n = doc.ev.displays.count
        return n == 0 ? "No TVs yet" : "\(doc.tvsOn) of \(n) TV\(n == 1 ? "" : "s") on"
    }
    private var forced: Bool { doc.live?.live.force.values.contains { $0.isOn } ?? false }
    private var phoneLive: [Int: String] { doc.live?.golive ?? [:] }

    var body: some View {
        Group { if wide { wideBody } else { narrowBody } }
            .background(FC.paper)
            .background(GeometryReader { g in Color.clear.preference(key: PageWidthKey.self, value: g.size.width) })
            .onPreferenceChange(PageWidthKey.self) { width = $0 }
            .task { await tvs.load(doc); while !Task.isCancelled { try? await Task.sleep(for: .seconds(60)); await tvs.load(doc) } }
            .sheet(isPresented: $adding) {
                AddTVFlow(doc: doc, tvs: tvs) { id in adding = false; if let id { picked = id } }
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $allSending) {
                SendSheet(target: "every TV", choices: doc.pageChoices, places: places) { page, mins, place in
                    let ids: Any = place.map { p in doc.ev.displays.filter { $0.place.caseInsensitiveCompare(p) == .orderedSame }.map(\.id) } ?? "*"
                    sendToTVs(doc, ids, page, mins, to: place.map { "the TVs at \($0)" } ?? "every TV")
                }
            }
            .fullScreenCover(isPresented: $goingLive) {
                GoLiveView(model: GoLiveModel(holes: GoLiveHole.from(doc.ev.course.holes)) { [doc] body in
                    var b = body
                    let op = b.removeValue(forKey: "op") as? String ?? ""
                    return try await Net.desk(doc.id, doc.key, op, b)
                }, liveNow: phoneLive)
            }
    }

    // MARK: iPhone (and a narrow iPad): one column

    private var narrowBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("\(kicker) · \(doc.ev.name)").font(.subheadline.weight(.semibold)).foregroundStyle(doc.tvsOn > 0 ? FC.ok : FC.muted)
                    .padding(.top, -6)
                actions
                VStack(alignment: .leading, spacing: 7) {
                    CardTitle("TVs").padding(.leading, 4)
                    if doc.ev.displays.isEmpty {
                        Text("Add each TV at the club once. It shows this tournament, and every one after it.")
                            .font(.subheadline).foregroundStyle(FC.muted).padding(.horizontal, 4)
                    }
                    TVList(doc: doc, add: { adding = true }) { d in
                        NavigationLink { TVScreen(doc: doc, tvs: tvs, id: d.id) } label: {
                            HStack(spacing: 0) { row(d); Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(FC.muted).padding(.trailing, 12) }
                        }
                        .buttonStyle(.plain)
                    }
                }
                VStack(alignment: .leading, spacing: 7) {
                    CardTitle("On the TVs").padding(.leading, 4)
                    VStack(spacing: 0) {
                        ForEach(ScreensPart.allCases) { p in
                            NavigationLink { PartScreen(doc: doc, part: p) } label: { partRow(p, last: p == ScreensPart.allCases.last) }.buttonStyle(.plain)
                        }
                    }
                    .background(FC.card, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(FC.line))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 110)
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .navigationTitle("Screens")
        .navigationBarTitleDisplayMode(.large)
    }

    /// Show on every TV, Back to normal, Go live
    private var actions: some View {
        HStack(spacing: 8) {
            bigButton("Show on Every TV", "tv", fill: FC.green, ink: FC.onGreen) { allSending = true }
                .disabled(doc.ev.displays.isEmpty)
            bigButton("Back to Normal", "arrow.uturn.backward", fill: FC.card, ink: forced ? FC.ink : FC.muted) { sendToTVs(doc, "*", nil, 0, to: "every TV") }
                .disabled(doc.ev.displays.isEmpty)
            bigButton(phoneLive.isEmpty ? "Go Live" : "Live now", "record.circle", fill: FC.red, ink: .white) { goingLive = true }
        }
    }
    private func bigButton(_ t: String, _ icon: String, fill: Color, ink: Color, _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold))
                Text(t).font(.system(size: 13, weight: .semibold)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
            }
            .foregroundStyle(ink).frame(maxWidth: .infinity, minHeight: 74).padding(.horizontal, 4)
            .background(fill, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(fill == FC.card ? FC.line : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    private func row(_ d: Display, selected: Bool = false) -> some View {
        TVRow(display: d, online: doc.live?.online[d.id] ?? 0, force: doc.live?.live.force[d.id], choices: doc.pageChoices, selected: selected)
    }
    private func partRow(_ p: ScreensPart, last: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: p.icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(p == .sponsors ? FC.onFlag : .white)
                .frame(width: 30, height: 30).background(p.color, in: RoundedRectangle(cornerRadius: 8))
            Text(p.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(FC.ink)
            Spacer()
            badge(p)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(FC.muted)
        }
        .padding(.horizontal, 12).frame(minHeight: 50).contentShape(Rectangle())
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(FC.hairline).frame(height: 1).padding(.leading, 54) } }
    }
    @ViewBuilder private func badge(_ p: ScreensPart) -> some View {
        switch p {
        case .sponsors where !doc.ev.sponsors.isEmpty: Text("\(doc.ev.sponsors.count)").font(.subheadline).foregroundStyle(FC.muted)
        case .cameras where !phoneLive.isEmpty:
            Text("LIVE \(phoneLive.keys.sorted().map { $0 == 0 ? "CLUBHOUSE" : String($0) }.joined(separator: ", "))")
                .font(.system(size: 10, weight: .heavy)).foregroundStyle(FC.red).padding(.horizontal, 7).padding(.vertical, 3).background(FC.red.opacity(0.12), in: Capsule())
        case .announcement where !(doc.live?.flash?.text ?? "").isEmpty: Text("Showing").font(.subheadline).foregroundStyle(FC.ok)
        case .fund where doc.ev.fund.on: Text("On").font(.subheadline).foregroundStyle(FC.muted)
        default: EmptyView()
        }
    }

    // MARK: a wide iPad: tabs, and the TV list beside the picked TV

    private var wideBody: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Screens").font(FC.display(34)).foregroundStyle(FC.ink)
                    Text(kicker).font(.subheadline.weight(.semibold)).foregroundStyle(doc.tvsOn > 0 ? FC.ok : FC.muted)
                }
                Spacer()
                Button { openURL(doc.boardURL) } label: { Label("Open the Board", systemImage: "arrow.up.right.square") }.buttonStyle(PlainCardButton())
                Button { sendToTVs(doc, "*", nil, 0, to: "every TV") } label: { Label("Back to Normal", systemImage: "arrow.uturn.backward") }.buttonStyle(PlainCardButton())
                    .disabled(doc.ev.displays.isEmpty)
                Button { allSending = true } label: { Label("Show on Every TV…", systemImage: "tv") }.buttonStyle(GreenButton())
                    .disabled(doc.ev.displays.isEmpty)
                Button { goingLive = true } label: {
                    Label(phoneLive.isEmpty ? "Go Live" : "Live now", systemImage: "record.circle").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(minHeight: 44).background(FC.red, in: RoundedRectangle(cornerRadius: 10)).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    tab("TVs", "tvs", count: doc.ev.displays.count)
                    ForEach(ScreensPart.allCases) { p in tab(p.short, p.rawValue, count: p == .sponsors ? doc.ev.sponsors.count : 0, live: p == .cameras && !phoneLive.isEmpty) }
                }
                .padding(.horizontal, 20).padding(.vertical, 8)
            }
            .background(FC.paper2.opacity(0.5))
            .overlay(alignment: .bottom) { Rectangle().fill(FC.line).frame(height: 1) }
            if let p = ScreensPart(rawValue: part) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) { p.view(doc) }
                        .padding(20).padding(.bottom, 90).frame(maxWidth: 760).frame(maxWidth: .infinity)
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            CardTitle("TVs at the club").padding(.leading, 4)
                            TVList(doc: doc, add: { adding = true }) { d in
                                Button { picked = d.id } label: { row(d, selected: d.id == shown) }.buttonStyle(.plain)
                            }
                            Text("A TV you add once shows every tournament at the club. What it shows is picked for each tournament.")
                                .font(.footnote).foregroundStyle(FC.muted).padding(.horizontal, 4)
                        }
                        .padding(16).padding(.bottom, 90)
                    }
                    .frame(width: min(360, max(300, width * 0.34)))
                    Rectangle().fill(FC.line).frame(width: 1)
                    ScrollView {
                        Group {
                            if let id = shown { TVDetail(doc: doc, tvs: tvs, id: id) { picked = nil }.id(id) }
                            else {
                                VStack(spacing: 12) {
                                    Image(systemName: "tv").font(.system(size: 40)).foregroundStyle(FC.muted)
                                    Text("No TVs yet").font(FC.display(30)).foregroundStyle(FC.ink)
                                    Text("Add each TV at the club once. It shows this tournament, and every one after it.").font(.subheadline).foregroundStyle(FC.muted).multilineTextAlignment(.center)
                                    Button("Add a TV") { adding = true }.buttonStyle(GreenButton())
                                }
                                .frame(maxWidth: .infinity).padding(.top, 60)
                            }
                        }
                        .padding(22).padding(.bottom, 90).frame(maxWidth: 720).frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }
    /// the picked TV, or the first one
    private var shown: String? { picked.flatMap { p in doc.ev.displays.contains { $0.id == p } ? p : nil } ?? doc.ev.displays.first?.id }
    private func tab(_ t: String, _ key: String, count: Int = 0, live: Bool = false) -> some View {
        let on = part == key || (key == "tvs" && ScreensPart(rawValue: part) == nil)
        return Button { part = key } label: {
            HStack(spacing: 5) {
                Text(t).font(.system(size: 14, weight: on ? .semibold : .regular))
                if count > 0 { Text("\(count)").font(.system(size: 11, weight: .semibold)).padding(.horizontal, 6).padding(.vertical, 1).background(FC.paper2, in: Capsule()) }
                if live { Text("LIVE").font(.system(size: 9, weight: .heavy)).foregroundStyle(FC.red).padding(.horizontal, 5).padding(.vertical, 2).background(FC.red.opacity(0.12), in: Capsule()) }
            }
            .foregroundStyle(on ? FC.ink : FC.muted).padding(.horizontal, 13).frame(height: 32)
            .background(on ? FC.card : .clear, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: on ? .black.opacity(0.1) : .clear, radius: 2, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A page pushed from Screens on iPhone, with the notices and Save that the tournament's pages have.
private struct PushedPage<Content: View>: View {
    let doc: DeskDoc
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { content }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 110).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .background(FC.paper)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                NoticeBar(text: doc.notice)
                if doc.dirty { SaveBar(doc: doc) }
            }
            .padding(.bottom, 10)
            .animation(.snappy, value: doc.notice)
            .animation(.snappy, value: doc.dirty)
        }
    }
}

/// One TV's page (iPhone).
private struct TVScreen: View {
    @Bindable var doc: DeskDoc
    let tvs: ClubTVs
    let id: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        PushedPage(doc: doc, title: "") { TVDetail(doc: doc, tvs: tvs, id: id) { dismiss() } }
    }
}

/// Sponsors, the announcement, cameras, fundraising or how the TVs look (iPhone).
private struct PartScreen: View {
    @Bindable var doc: DeskDoc
    let part: ScreensPart
    var body: some View { PushedPage(doc: doc, title: part.title) { part.view(doc) } }
}

/// Switch one TV, a list of TVs or every TV ("*"); page nil = back to normal.
@MainActor func send(_ doc: DeskDoc, _ display: Any, _ page: PageRef?, _ mins: Int, to: String) { sendToTVs(doc, display, page, mins, to: to) }

struct AnyStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ s: S) { make = { AnyView(s.makeBody(configuration: $0)) } }
    func makeBody(configuration c: Configuration) -> some View { make(c) }
}

/// Show something else for a bit: big buttons for what, then one tap for how long.
struct SendSheet: View {
    var target: String
    var choices: PageChoices
    var places: [String]
    var send: (PageRef, Int, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var page = PageRef(k: "lb")
    @State private var place = ""
    private let quick: [(String, String, String)] = [("lb", "Leaderboard", "list.number"), ("p3", "Par 3 camera", "video"), ("contests", "Contests", "flag.2.crossed"),
                                                     ("sponsors", "Sponsors", "star"), ("fund", "Fundraising", "heart"), ("schedule", "Schedule", "clock"), ("skins", "Skins", "dollarsign.circle")]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !places.isEmpty {
                        Picker("Which TVs", selection: $place) { Text("Every TV").tag(""); ForEach(places, id: \.self) { Text("TVs at \($0)").tag($0) } }.pickerStyle(.menu)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                        ForEach(quick, id: \.0) { q in
                            let on = page.k == q.0 || (q.0 == "sponsors" && page.k == "sponsor")
                            Button { page = PageRef(k: q.0) } label: {
                                VStack(spacing: 4) { Image(systemName: q.2).font(.system(size: 20, weight: .semibold)); Text(q.1).font(.system(size: 13, weight: .semibold)) }
                                    .foregroundStyle(on ? FC.onGreen : FC.ink).frame(maxWidth: .infinity, minHeight: 72)
                                    .background(on ? FC.green : FC.paper2.opacity(0.7), in: RoundedRectangle(cornerRadius: 11))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if page.k == "lb" && choices.flights.count > 1 {
                        Picker("Which flight", selection: $page.fl) { Text("All flights").tag(""); ForEach(choices.flights, id: \.self) { Text("Flight \($0)").tag($0) } }.pickerStyle(.segmented)
                    }
                    if page.k == "p3" && choices.p3.count > 1 {
                        Picker("Which hole", selection: $page.hole) { Text("Each in turn").tag(0); ForEach(choices.p3, id: \.self) { Text("Hole \($0)").tag($0) } }.pickerStyle(.segmented)
                    }
                    if (page.k == "sponsors" || page.k == "sponsor") && choices.sponsors.count > 1 {
                        Picker("Which sponsor", selection: Binding(get: { page.k == "sponsor" ? page.sponsor : "" }, set: { v in page = v.isEmpty ? PageRef(k: "sponsors") : PageRef(k: "sponsor", sponsor: v) })) {
                            Text("All of them, in turn").tag(""); ForEach(choices.sponsors, id: \.id) { Text($0.name).tag($0.id) }
                        }
                        .pickerStyle(.menu)
                    }
                    CardTitle("For how long?")
                    ForEach(SendLength.allCases) { l in
                        Button(l.title) { send(page, l.rawValue, place.isEmpty ? nil : place); dismiss() }.buttonStyle(GreenButton(full: true))
                    }
                    Help("Then it goes back to normal by itself (or press Back to Normal).")
                }
                .padding(16)
            }
            .background(FC.paper)
            .navigationTitle("Show on \(place.isEmpty ? target : "TVs at \(place)")").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}

/// Customize: the pages in order (drag to reorder), each with its flight, hole or sponsor and seconds; copy to other TVs.
struct PlaylistList: View {
    @Binding var playlist: [PageRef]
    var choices: PageChoices
    var others: [(id: String, name: String)]
    var copyTo: ([String]) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if playlist.isEmpty { Text("Nothing picked: this TV shows everything in turn.").font(.footnote).foregroundStyle(FC.muted) }
            ForEach(playlist.indices, id: \.self) { k in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(k + 1)").font(.caption.weight(.bold)).foregroundStyle(FC.muted).frame(width: 18)
                        Picker("", selection: $playlist[k].k) { ForEach(PAGE_NAMES, id: \.0) { Text($0.1).tag($0.0) } }.labelsHidden()
                            .onChange(of: playlist[k].k) { _, _ in playlist[k].fl = ""; playlist[k].hole = 0; playlist[k].sponsor = "" }
                        Spacer()
                        Button { if k > 0 { playlist.swapAt(k, k - 1) } } label: { Image(systemName: "arrow.up") }.disabled(k == 0)
                        Button { if k < playlist.count - 1 { playlist.swapAt(k, k + 1) } } label: { Image(systemName: "arrow.down") }.disabled(k == playlist.count - 1)
                        Button(role: .destructive) { playlist.remove(at: k) } label: { Image(systemName: "minus.circle") }
                    }
                    HStack {
                        switch playlist[k].k {
                        case "lb" where !choices.flights.isEmpty:
                            Picker("", selection: $playlist[k].fl) { Text("All flights").tag(""); ForEach(choices.flights, id: \.self) { Text("Flight \($0)").tag($0) } }.labelsHidden()
                        case "p3", "cam":
                            Picker("", selection: $playlist[k].hole) { Text("Each in turn").tag(0); ForEach(playlist[k].k == "p3" ? choices.p3 : choices.holes, id: \.self) { Text("Hole \($0)").tag($0) } }.labelsHidden()
                        case "sponsor":
                            Picker("", selection: $playlist[k].sponsor) { Text("Pick one").tag(""); ForEach(choices.sponsors, id: \.id) { Text($0.name).tag($0.id) } }.labelsHidden()
                        default: EmptyView()
                        }
                        Spacer()
                        Stepper("\(playlist[k].secs) s", value: $playlist[k].secs, in: 4...300, step: 2).fixedSize()
                    }
                    .font(.subheadline)
                }
                .padding(10).background(FC.paper2.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            }
            HStack {
                Button { playlist.append(PageRef(k: "lb", secs: 15)) } label: { Label("Add a Page", systemImage: "plus") }
                Spacer()
                if !others.isEmpty {
                    Menu("Copy to…") {
                        Button("Every Other TV") { copyTo(others.map(\.id)) }
                        ForEach(others, id: \.id) { o in Button(o.name.isEmpty ? "TV" : o.name) { copyTo([o.id]) } }
                    }
                    .disabled(playlist.isEmpty)
                }
            }
            .font(.subheadline.weight(.semibold))
            if !playlist.isEmpty { Text("Goes round every \(playlist.reduce(0) { $0 + $1.secs }) seconds").font(.caption).foregroundStyle(FC.muted) }
        }
        .padding(.top, 8)
    }
}
