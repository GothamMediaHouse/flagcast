import SwiftUI

// The club's screens as a wall of cards (the desk's Screens page and Admin → Screens & phones): each TV with whether it's
// on, where it hangs, what it shows now, its playlist, and Send now (one page for 5 or 15 minutes, or until you change it,
// then back to its playlist) to that screen, a group of screens or every screen.

/// What a screen can be sent to for one tournament.
struct PageChoices {
    var flights: [String] = []
    var p3: [Int] = []
    var holes: [Int] = Array(1...18)
    var sponsors: [(id: String, name: String)] = []

    func label(_ p: PageRef) -> String {
        let n = PAGE_NAMES.first { $0.0 == p.k }?.1 ?? p.k
        switch p.k {
        case "lb": return p.fl.isEmpty ? n : "\(n) · Flight \(p.fl)"
        case "p3": return p.hole > 0 ? "Par 3 camera · Hole \(p.hole)" : "Par 3 cameras, each in turn"
        case "cam": return p.hole > 0 ? "Camera · Hole \(p.hole)" : "Cameras, each in turn"
        case "sponsor": return sponsors.first { $0.id == p.sponsor }.map { "Sponsor · \($0.name)" } ?? "One sponsor"
        default: return n
        }
    }
    static func icon(_ k: String) -> String {
        switch k {
        case "lb": "list.number"; case "p3", "cam": "video"; case "contests": "flag.2.crossed"; case "skins": "dollarsign.circle"
        case "fund": "heart"; case "sponsors", "sponsor": "star"; case "schedule": "clock"; default: "rectangle"
        }
    }
}

/// How long Send now keeps the page on before the screen goes back to its playlist.
enum SendLength: Int, CaseIterable, Identifiable {
    case five = 5, fifteen = 15, changed = 0
    var id: Int { rawValue }
    var title: String { switch self { case .five: "5 min"; case .fifteen: "15 min"; case .changed: "Until I change it" } }
}

/// "Showing … until 3:42 PM" or "Playing its playlist".
func screenStatus(_ force: PageRef?, playlist: [PageRef], choices: PageChoices) -> String {
    if let f = force, f.isOn {
        let page = choices.label(f)
        return f.until > 0 ? "\(page) until \(Date(timeIntervalSince1970: f.until / 1000).formatted(date: .omitted, time: .shortened))" : "\(page), until you change it"
    }
    if playlist.isEmpty { return "Playing everything (no playlist)" }
    return "Playing its playlist · \(playlist.count) page\(playlist.count == 1 ? "" : "s")"
}

// MARK: - Send now

/// Pick a page (and its flight, hole or sponsor) and how long, then send it.
struct SendNowPanel: View {
    var target: String
    var choices: PageChoices
    var send: (PageRef, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var page = PageRef(k: "lb")
    @State private var length: SendLength = .fifteen

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send to \(target)").font(.headline)
            PagePicker(page: $page, choices: choices)
            Picker("For", selection: $length) { ForEach(SendLength.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            Text(length == .changed ? "It stays on until you send something else or put the screen back on its playlist." : "Then the screen goes back to its playlist by itself.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Send Now") { send(page, length.rawValue); dismiss() }.keyboardShortcut(.defaultAction)
                    .disabled(page.k == "sponsor" && page.sponsor.isEmpty)
            }
        }
        .padding(18).frame(width: 380)
    }
}

/// The page and, for the pages that have one, its flight, hole or sponsor.
struct PagePicker: View {
    @Binding var page: PageRef
    var choices: PageChoices
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            Picker(compact ? "" : "Page", selection: $page.k) { ForEach(PAGE_NAMES, id: \.0) { Text($0.1).tag($0.0) } }
                .labelsHidden(compact).frame(width: compact ? 170 : nil)
            switch page.k {
            case "lb":
                Picker("", selection: $page.fl) { Text("All flights").tag(""); ForEach(choices.flights, id: \.self) { Text("Flight \($0)").tag($0) } }
                    .labelsHidden().frame(width: 120).disabled(choices.flights.isEmpty)
            case "p3", "cam":
                Picker("", selection: $page.hole) {
                    Text("Each in turn").tag(0)
                    ForEach(page.k == "p3" ? choices.p3 : choices.holes, id: \.self) { Text("Hole \($0)").tag($0) }
                }
                .labelsHidden().frame(width: 130)
            case "sponsor":
                Picker("", selection: $page.sponsor) { Text("Pick one").tag(""); ForEach(choices.sponsors, id: \.id) { Text($0.name).tag($0.id) } }
                    .labelsHidden().frame(width: 160)
            default: EmptyView()
            }
        }
        .onChange(of: page.k) { _, _ in page.fl = ""; page.hole = 0; page.sponsor = "" }
    }
}

private extension View {
    @ViewBuilder func labelsHidden(_ on: Bool) -> some View { if on { self.labelsHidden() } else { self } }
}

// MARK: - the card

/// A small picture of what the screen shows: the page's icon and name on the green, or the start of its playlist.
struct ScreenPreview: View {
    var force: PageRef?
    var playlist: [PageRef]
    var choices: PageChoices
    var online: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: [FC.green2, FC.green], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let f = force, f.isOn {
                VStack(spacing: 6) {
                    Image(systemName: PageChoices.icon(f.k)).font(.system(size: 22, weight: .semibold)).foregroundStyle(FC.flag)
                    Text(choices.label(f)).font(FC.display(17)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
                }
                .padding(8)
            } else if playlist.isEmpty {
                VStack(spacing: 6) { Image(systemName: "square.grid.2x2").font(.system(size: 20)); Text("Everything").font(FC.display(17)) }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(playlist.prefix(4).enumerated()), id: \.offset) { i, p in
                        HStack(spacing: 5) {
                            Image(systemName: PageChoices.icon(p.k)).font(.system(size: 9)).frame(width: 12)
                            Text(choices.label(p)).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                        }
                        .opacity(i == 0 ? 1 : 0.7)
                    }
                    if playlist.count > 4 { Text("+ \(playlist.count - 4) more").font(.system(size: 9)).opacity(0.6) }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(FC.onGreen)
        .frame(width: 168, height: 94)
        .overlay(alignment: .topTrailing) {
            if force?.isOn == true { LiveChip(text: "SENT").scaleEffect(0.8).padding(4) }
        }
        .overlay { if !online { Color.black.opacity(0.35) } }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(FC.line))
    }
}

/// One screen: on or off, its name and where it hangs (title), what it shows now with Send now and Back to Playlist,
/// its link, and below it whatever the page adds (the playlist editor on the desk).
struct ScreenCard<Title: View, Details: View>: View {
    var name: String
    var online: Int
    var force: PageRef?
    var playlist: [PageRef]
    var url: URL?
    var choices: PageChoices
    var send: (PageRef?, Int) -> Void
    @ViewBuilder var title: Title
    @ViewBuilder var details: Details
    @State private var sending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(online > 0 ? FC.ok : FC.muted.opacity(0.4)).frame(width: 9, height: 9).padding(.top, 6)
                    .help(online > 0 ? "On now\(online > 1 ? " (\(online) open)" : "")" : "Not connected")
                title
                Spacer(minLength: 4)
                if let url {
                    Button { copy(url.absoluteString) } label: { Image(systemName: "link") }.buttonStyle(.borderless).help("Copy this screen’s link (open it full screen on the TV)")
                    Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "arrow.up.right.square") }.buttonStyle(.borderless).help("Open this screen here")
                }
            }
            HStack(alignment: .top, spacing: 14) {
                ScreenPreview(force: force, playlist: playlist, choices: choices, online: online > 0)
                VStack(alignment: .leading, spacing: 8) {
                    Text(online > 0 ? "ON NOW" : "NOT CONNECTED").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(online > 0 ? FC.ok : FC.muted)
                    TimelineView(.periodic(from: .now, by: 15)) { _ in
                        Text(screenStatus(force, playlist: playlist, choices: choices)).font(.system(size: 13, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 6) {
                        Button("Send Now…") { sending = true }.buttonStyle(GreenButton())
                            .popover(isPresented: $sending, arrowEdge: .bottom) { SendNowPanel(target: name.isEmpty ? "this screen" : name, choices: choices) { send($0, $1) } }
                        if force?.isOn == true { Button("Back to Playlist") { send(nil, 0) }.buttonStyle(PlainCardButton()) }
                    }
                }
            }
            details
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .raisedCard()
    }
}

/// Above the wall: Send now to every screen or a group, and put them all back on their playlists.
struct SendToManyBar: View {
    var groups: [String]
    var choices: PageChoices
    /// nil = every screen, else a group's name; page nil = back to the playlists
    var send: (String?, PageRef?, Int) -> Void
    @State private var target = "*"
    @State private var sending = false
    private var targetName: String { target == "*" ? "every screen" : "the \(target) screens" }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tv.and.mediabox").foregroundStyle(FC.muted)
            Text("Several screens at once").font(.system(size: 14, weight: .bold))
            Picker("", selection: $target) {
                Text("Every screen").tag("*")
                if !groups.isEmpty { Divider(); ForEach(groups, id: \.self) { Text("Group: \($0)").tag($0) } }
            }
            .labelsHidden().frame(width: 200)
            Spacer()
            Button("Back to Playlists") { send(target == "*" ? nil : target, nil, 0) }.buttonStyle(PlainCardButton())
            Button("Send Now…") { sending = true }.buttonStyle(GreenButton())
                .popover(isPresented: $sending, arrowEdge: .bottom) { SendNowPanel(target: targetName, choices: choices) { send(target == "*" ? nil : target, $0, $1) } }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .raisedCard()
    }
}

// MARK: - the playlist (desk)

/// Ready-made playlists: (name, pages). An empty list plays everything.
let READY_PLAYLISTS: [(String, [PageRef])] = [
    ("Leaderboard only", [PageRef(k: "lb", secs: 20)]),
    ("Leaderboard and sponsors", [PageRef(k: "lb", secs: 15), PageRef(k: "sponsors", secs: 8)]),
    ("Par 3 cameras", [PageRef(k: "p3", secs: 20)]),
    ("Leaderboard, cameras, contests", [PageRef(k: "lb", secs: 15), PageRef(k: "p3", secs: 20), PageRef(k: "contests", secs: 10), PageRef(k: "sponsors", secs: 8)]),
    ("Everything (no list)", []),
]

/// A screen's playlist: drag the handle to reorder; each page with its flight, hole or sponsor and seconds.
struct PlaylistEditor: View {
    @Binding var playlist: [PageRef]
    var choices: PageChoices
    /// the other screens, to copy this list to
    var others: [(id: String, name: String)]
    var copyTo: ([String]) -> Void
    @State private var dropTarget: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                CardTitle("Playlist")
                Spacer()
                Menu("Ready-made") { ForEach(READY_PLAYLISTS, id: \.0) { r in Button(r.0) { playlist = r.1 } } }.fixedSize().controlSize(.small)
                if !others.isEmpty {
                    Menu("Copy to…") {
                        Button("Every Other Screen") { copyTo(others.map(\.id)) }
                        Divider()
                        ForEach(others, id: \.id) { o in Button(o.name.isEmpty ? "Unnamed screen" : o.name) { copyTo([o.id]) } }
                    }
                    .fixedSize().controlSize(.small).disabled(playlist.isEmpty)
                }
            }
            if playlist.isEmpty { Text("No list: this screen plays everything in turn.").font(.callout).foregroundStyle(FC.muted) }
            ForEach(playlist.indices, id: \.self) { k in
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal").foregroundStyle(FC.muted).frame(width: 16).contentShape(Rectangle())
                        .draggable(String(k)).help("Drag to move")
                    Text("\(k + 1)").monospacedDigit().foregroundStyle(FC.muted).frame(width: 16)
                    PagePicker(page: $playlist[k], choices: choices, compact: true)
                    Spacer(minLength: 4)
                    Stepper("\(playlist[k].secs) s", value: $playlist[k].secs, in: 4...300, step: 2).monospacedDigit().fixedSize()
                    Button(role: .destructive) { playlist.remove(at: k) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).help("Take this page off")
                }
                .padding(.vertical, 2)
                .overlay(alignment: .top) { if dropTarget == k { Rectangle().fill(FC.primary).frame(height: 2).offset(y: -3) } }
                .dropDestination(for: String.self) { items, _ in
                    guard let s = items.first, let from = Int(s), playlist.indices.contains(from), from != k else { return false }
                    withAnimation(.snappy) { let p = playlist.remove(at: from); playlist.insert(p, at: from < k ? k - 1 : k) }
                    return true
                } isTargeted: { on in dropTarget = on ? k : (dropTarget == k ? nil : dropTarget) }
            }
            HStack {
                Button { playlist.append(PageRef(k: "lb", secs: 15)) } label: { Label("Add a Page", systemImage: "plus") }.controlSize(.small)
                Spacer()
                if !playlist.isEmpty {
                    Text("One loop: \(playlist.reduce(0) { $0 + $1.secs }) s").font(.caption).foregroundStyle(FC.muted)
                }
            }
            // dropping below the last page moves it to the end
            Color.clear.frame(height: 6)
                .dropDestination(for: String.self) { items, _ in
                    guard let s = items.first, let from = Int(s), playlist.indices.contains(from) else { return false }
                    withAnimation(.snappy) { let p = playlist.remove(at: from); playlist.append(p) }
                    return true
                }
        }
    }
}
