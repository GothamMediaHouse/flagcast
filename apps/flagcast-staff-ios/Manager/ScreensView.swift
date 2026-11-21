import SwiftUI

/// Screens: every TV at the club as a card. "What should this TV show?" picture tiles, Show something else for a bit
/// and Back to normal, Where is it?, Set up this TV, and the detail under Customize. (Engineering is Flagcast's: Admin.)
struct ScreensView: View {
    var body: some View {
        WithTournament { doc in ScreensPage(doc: doc) }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { TournamentMenu() } }
    }
}

private struct ScreensPage: View {
    @Bindable var doc: DeskDoc
    @Environment(DeskNav.self) private var nav
    @State private var allSending = false

    static let PLACES = ["Clubhouse", "Bar", "Grill room", "Pro shop", "Tent", "Patio", "Locker room", "Hole 7 tee", "Hole 18 green"]
    private var choices: PageChoices { doc.pageChoices }
    private var saved: Set<String> { Set((doc.live?.displays ?? []).map(\.id)) }
    private var places: [String] {
        var seen: [String] = []
        for d in doc.ev.displays where !d.place.isEmpty && !seen.contains(where: { $0.caseInsensitiveCompare(d.place) == .orderedSame }) { seen.append(d.place) }
        return seen
    }

    var body: some View {
        PhotoPage(image: doc.picture.image, kicker: "\(doc.ev.displays.filter { (doc.live?.online[$0.id] ?? 0) > 0 }.count) of \(doc.ev.displays.count) on",
                  title: "TVs", sub: "What the TVs at the club show", height: 220) {
            EmptyView()
        } content: {
            if doc.ev.displays.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tv").font(.system(size: 40)).foregroundStyle(FC.muted)
                    Text("No TVs yet").font(FC.display(32))
                    Text("Add each TV at the club. You’ll pick what it shows, and we’ll show you how to put Flagcast on it.")
                        .font(.subheadline).foregroundStyle(FC.muted).multilineTextAlignment(.center)
                    Button("Add Your First TV") { addTV() }.buttonStyle(GreenButton())
                }
                .frame(maxWidth: .infinity).card(padding: 24)
            } else {
                if doc.ev.displays.count > 1 { allAtOnce }
                ForEach($doc.ev.displays) { $d in TVCard(display: $d, doc: doc, saved: saved.contains(d.id), places: Self.PLACES + places.filter { !Self.PLACES.contains($0) }) }
                Button { addTV() } label: { Label("Add Another TV", systemImage: "plus") }.buttonStyle(PlainCardButton(full: true))
            }
        }
    }

    private var allAtOnce: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle("All at once")
            HStack(spacing: 8) {
                Button("Back to Normal") { send(doc, "*", nil, 0, to: "every TV") }.buttonStyle(PlainCardButton(full: true))
                Button("Show Something Else…") { allSending = true }.buttonStyle(GreenButton(full: true))
            }
            .sheet(isPresented: $allSending) {
                SendSheet(target: "every TV", choices: choices, places: places) { page, mins, place in
                    let ids: Any = place.map { p in doc.ev.displays.filter { $0.place.caseInsensitiveCompare(p) == .orderedSame && saved.contains($0.id) }.map(\.id) } ?? "*"
                    send(doc, ids, page, mins, to: place.map { "the TVs at \($0)" } ?? "every TV")
                }
            }
        }
        .card()
    }

    private func addTV() { doc.ev.displays.append(Display(name: "TV \(doc.ev.displays.count + 1)", playlist: ShowTile.mix.pages)) }
}

/// Switch one TV, a list of TVs or every TV ("*"); page nil = back to normal.
@MainActor func send(_ doc: DeskDoc, _ display: Any, _ page: PageRef?, _ mins: Int, to: String) {
    if let ids = display as? [String], ids.isEmpty { doc.flash("No saved TVs there yet."); return }
    var b: [String: Any] = ["display": display, "page": pageDict(page)]
    if page != nil, mins > 0 { b["mins"] = mins }
    let done = page == nil ? "Back to normal: \(to)." : mins > 0 ? "On \(to) for \(mins) minutes." : "On \(to) until you switch back."
    Task { await doc.day("screen", b, done: done) }
}

/// One TV: what it shows now (with Show something else and Back to normal), its name and where it is, the picture
/// tiles for what it shows normally, Set up this TV, and Customize.
private struct TVCard: View {
    @Binding var display: Display
    let doc: DeskDoc
    let saved: Bool
    let places: [String]
    @State private var sending = false
    @State private var setup = false
    @State private var customize = false

    private var online: Int { doc.live?.online[display.id] ?? 0 }
    private var force: PageRef? { doc.live?.live.force[display.id] }
    private var url: URL { URL(string: "\(doc.boardURL.absoluteString)?screen=\(display.id)")! }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Preview(force: force, playlist: display.playlist, choices: doc.pageChoices, online: online > 0)
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Name this TV", text: $display.name).font(FC.display(26))
                    Menu {
                        ForEach(places, id: \.self) { p in Button(p) { display.place = p; display.group = p } }
                        if !display.place.isEmpty { Divider(); Button("Not set", role: .destructive) { display.place = ""; display.group = "" } }
                    } label: {
                        Label(display.place.isEmpty ? "Where is it?" : display.place, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(display.place.isEmpty ? FC.link : FC.muted)
                    }
                    TimelineView(.periodic(from: .now, by: 15)) { _ in
                        Text(online > 0 ? screenStatus(force, playlist: display.playlist, choices: doc.pageChoices) : "This TV isn’t showing Flagcast yet.")
                            .font(.footnote).foregroundStyle(FC.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: 8) {
                if force?.isOn == true { Button("Back to Normal") { go(nil, 0) }.buttonStyle(GreenButton(full: true)) }
                Button("Show Something Else…") { sending = true }.buttonStyle(force?.isOn == true ? AnyStyle(PlainCardButton(full: true)) : AnyStyle(GreenButton(full: true)))
            }
            if online == 0 { Button { setup = true } label: { Label("Set Up This TV", systemImage: "tv.badge.wifi") }.buttonStyle(PlainCardButton(full: true)) }
            Divider().overlay(FC.hairline)
            Text("What should this TV show?").font(.subheadline.weight(.bold))
            Tiles(playlist: $display.playlist)
            DisclosureGroup(isExpanded: $customize) {
                PlaylistList(playlist: $display.playlist, choices: doc.pageChoices,
                             others: doc.ev.displays.filter { $0.id != display.id }.map { ($0.id, $0.name) },
                             copyTo: { ids in let l = display.playlist; for i in doc.ev.displays.indices where ids.contains(doc.ev.displays[i].id) { doc.ev.displays[i].playlist = l }; doc.flash("Copied. Save to put it on those TVs.") })
                Button("Remove This TV", role: .destructive) { let id = display.id; doc.ev.displays.removeAll { $0.id == id } }.font(.subheadline).padding(.top, 6)
            } label: { Text("Customize…").font(.subheadline.weight(.semibold)).foregroundStyle(FC.link) }
            if !saved { Label("New TV: press Save to switch it on.", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(FC.muted) }
        }
        .card()
        .sheet(isPresented: $sending) {
            SendSheet(target: display.name.isEmpty ? "this TV" : display.name, choices: doc.pageChoices, places: []) { page, mins, _ in go(page, mins) }
        }
        .sheet(isPresented: $setup) { NavigationStack { SetUpTV(name: display.name, url: url) } }
    }
    private func go(_ page: PageRef?, _ mins: Int) {
        if !saved { doc.flash("Press Save first, then you can switch this TV."); return }
        send(doc, display.id, page, mins, to: display.name.isEmpty ? "the TV" : display.name)
    }
}

struct AnyStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ s: S) { make = { AnyView(s.makeBody(configuration: $0)) } }
    func makeBody(configuration c: Configuration) -> some View { make(c) }
}

/// A small picture of what the TV shows now.
private struct Preview: View {
    var force: PageRef?
    var playlist: [PageRef]
    var choices: PageChoices
    var online: Bool
    var body: some View {
        ZStack {
            LinearGradient(colors: [FC.green2, FC.green], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 4) {
                if let f = force, f.isOn {
                    Image(systemName: PageChoices.icon(f.k)).font(.system(size: 20, weight: .semibold)).foregroundStyle(FC.flag)
                    Text(choices.label(f)).font(FC.display(15)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
                } else {
                    let t = ShowTile.matching(playlist)
                    Image(systemName: t?.icon ?? "rectangle.stack").font(.system(size: 20, weight: .semibold))
                    Text(t?.title ?? "Own mix").font(FC.display(15))
                }
            }
            .padding(6)
            if !online { Color.black.opacity(0.45) }
        }
        // off: a small tag in the corner, not on top of the picture's own words
        .overlay(alignment: .topLeading) {
            if !online {
                Text("OFF").font(.system(size: 8, weight: .heavy)).tracking(1).foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2).background(Color.black.opacity(0.6), in: Capsule()).padding(5)
                    .accessibilityLabel("This TV isn’t on")
            }
        }
        .foregroundStyle(FC.onGreen).frame(width: 116, height: 70).clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

/// The picture tiles: Mix (recommended), Leaderboard, Par 3 camera, Sponsors, Contests.
private struct Tiles: View {
    @Binding var playlist: [PageRef]
    var body: some View {
        let on = ShowTile.matching(playlist)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
            ForEach(ShowTile.allCases) { t in
                let sel = on == t
                Button { withAnimation(.snappy) { playlist = t.pages } } label: {
                    VStack(spacing: 4) {
                        Image(systemName: t.icon).font(.system(size: 20, weight: .semibold))
                        Text(t.title).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        Text(t.note).font(.system(size: 10)).opacity(0.75).lineLimit(1)
                    }
                    .foregroundStyle(sel ? FC.onGreen : FC.ink).frame(maxWidth: .infinity, minHeight: 78)
                    .background(sel ? FC.green : FC.paper2.opacity(0.7), in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(sel ? FC.flag : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
    }
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

/// How to put Flagcast on a TV: three steps and one button to send the link.
private struct SetUpTV: View {
    var name: String
    var url: URL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                step(1, "Send yourself the TV’s link", "Text or email it to yourself so you can open it on the TV.")
                HStack {
                    ShareLink(item: url) { Label("Send the Link", systemImage: "square.and.arrow.up") }.buttonStyle(GreenButton(full: true))
                    Button { copy(url.absoluteString) } label: { Label("Copy", systemImage: "doc.on.doc") }.buttonStyle(PlainCardButton())
                }
                step(2, "Open it in the TV’s web browser", "Or on the computer or stick plugged into the TV.")
                step(3, "Make it full screen", "This TV’s card says it’s on once the TV shows Flagcast.")
            }
            .padding(20)
        }
        .background(FC.paper)
        .navigationTitle("Put Flagcast on \(name.isEmpty ? "this TV" : name)").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
    private func step(_ n: Int, _ t: String, _ sub: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(FC.display(22)).foregroundStyle(FC.onGreen).frame(width: 34, height: 34).background(FC.green, in: Circle())
            VStack(alignment: .leading, spacing: 2) { Text(t).font(.headline); Text(sub).font(.subheadline).foregroundStyle(FC.muted) }
        }
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
