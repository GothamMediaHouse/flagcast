import SwiftUI

// The club's screens as a wall of cards (the desk's Screens page and Admin → Screens & phones): each TV with whether it's
// on, where it hangs, what it shows now, its playlist, and Send now (one page for 5 or 15 minutes, or until you change it,
// then back to its playlist) to that screen, a group of screens or every screen.

struct ShowTiles: View {
    @Binding var playlist: [PageRef]
    var body: some View {
        let on = ShowTile.matching(playlist)
        HStack(spacing: 8) {
            ForEach(ShowTile.allCases) { t in
                let sel = on == t
                Button { withAnimation(.snappy) { playlist = t.pages } } label: {
                    VStack(spacing: 4) {
                        Image(systemName: t.icon).font(.system(size: 18, weight: .semibold))
                        Text(t.title).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        Text(t.note).font(.system(size: 10)).opacity(0.75).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(sel ? FC.onGreen : FC.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(sel ? FC.green : FC.paper2.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(sel ? FC.flag : FC.line, lineWidth: sel ? 2 : 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - show something else for a bit

/// Pick what to show (big buttons), then how long: one click sends it.
struct SendNowPanel: View {
    var target: String
    var choices: PageChoices
    var send: (PageRef, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var page = PageRef(k: "lb")

    private let quick: [(String, String, String)] = [("lb", "Leaderboard", "list.number"), ("p3", "Par 3 camera", "video"), ("contests", "Contests", "flag.2.crossed"),
                                                     ("sponsors", "Sponsors", "star"), ("fund", "Fundraising", "heart"), ("schedule", "Schedule", "clock"), ("skins", "Skins", "dollarsign.circle")]
    private var needsSponsor: Bool { page.k == "sponsor" && page.sponsor.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Show on \(target)").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(quick, id: \.0) { q in
                    let on = page.k == q.0 || (q.0 == "sponsors" && page.k == "sponsor")
                    Button { page = PageRef(k: q.0) } label: {
                        VStack(spacing: 4) { Image(systemName: q.2).font(.system(size: 17, weight: .semibold)); Text(q.1).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8) }
                            .foregroundStyle(on ? FC.onGreen : FC.ink).frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(on ? FC.green : FC.paper2.opacity(0.6), in: RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            // only when there's a real choice to make
            if page.k == "lb" && choices.flights.count > 1 {
                Picker("Which flight", selection: $page.fl) { Text("All flights").tag(""); ForEach(choices.flights, id: \.self) { Text("Flight \($0)").tag($0) } }
            }
            if page.k == "p3" && choices.p3.count > 1 {
                Picker("Which hole", selection: $page.hole) { Text("Each in turn").tag(0); ForEach(choices.p3, id: \.self) { Text("Hole \($0)").tag($0) } }
            }
            if (page.k == "sponsors" || page.k == "sponsor") && choices.sponsors.count > 1 {
                Picker("Which sponsor", selection: Binding(get: { page.k == "sponsor" ? page.sponsor : "" }, set: { v in page = v.isEmpty ? PageRef(k: "sponsors") : PageRef(k: "sponsor", sponsor: v) })) {
                    Text("All of them, in turn").tag(""); ForEach(choices.sponsors, id: \.id) { Text($0.name).tag($0.id) }
                }
            }
            Divider()
            Text("For how long?").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(SendLength.allCases) { l in
                    Button(l.title) { send(page, l.rawValue); dismiss() }.buttonStyle(GreenButton()).disabled(needsSponsor)
                }
            }
            Text("Then it goes back to normal by itself (or press Back to Normal).").font(.caption).foregroundStyle(.secondary)
        }
        .padding(18).frame(width: 430)
    }
}

/// The page and, for the pages that have one, its flight, hole or sponsor (Customize).
struct PagePicker: View {
    @Binding var page: PageRef
    var choices: PageChoices

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: $page.k) { ForEach(PAGE_NAMES, id: \.0) { Text($0.1).tag($0.0) } }.labelsHidden().frame(width: 160)
            switch page.k {
            case "lb":
                if !choices.flights.isEmpty {
                    Picker("", selection: $page.fl) { Text("All flights").tag(""); ForEach(choices.flights, id: \.self) { Text("Flight \($0)").tag($0) } }.labelsHidden().frame(width: 110)
                }
            case "p3", "cam":
                Picker("", selection: $page.hole) {
                    Text("Each in turn").tag(0)
                    ForEach(page.k == "p3" ? choices.p3 : choices.holes, id: \.self) { Text("Hole \($0)").tag($0) }
                }
                .labelsHidden().frame(width: 120)
            case "sponsor":
                Picker("", selection: $page.sponsor) { Text("Pick one").tag(""); ForEach(choices.sponsors, id: \.id) { Text($0.name).tag($0.id) } }.labelsHidden().frame(width: 150)
            default: EmptyView()
            }
        }
        .onChange(of: page.k) { _, _ in page.fl = ""; page.hole = 0; page.sponsor = "" }
    }
}

// MARK: - the card

/// A small picture of what the TV shows now.
struct ScreenPreview: View {
    var force: PageRef?
    var playlist: [PageRef]
    var choices: PageChoices
    var online: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: [FC.green2, FC.green], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 6) {
                if let f = force, f.isOn {
                    Image(systemName: PageChoices.icon(f.k)).font(.system(size: 24, weight: .semibold)).foregroundStyle(FC.flag)
                    Text(choices.label(f)).font(FC.display(18)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
                } else {
                    let t = ShowTile.matching(playlist)
                    Image(systemName: t?.icon ?? "rectangle.stack").font(.system(size: 24, weight: .semibold))
                    Text(t?.title ?? "Own mix").font(FC.display(18))
                }
            }
            .padding(8)
            if !online { Color.black.opacity(0.45) }
        }
        // off: a small tag in the corner (it used to sit on top of the picture's own words)
        .overlay(alignment: .topLeading) {
            if !online {
                Text("OFF").font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Color.black.opacity(0.6), in: Capsule()).padding(6)
                    .accessibilityLabel("This TV isn’t on")
            }
        }
        .foregroundStyle(FC.onGreen)
        .frame(width: 150, height: 86)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// One TV: its name and where it is (title), what it shows now, Show Something Else and Back to Normal, then whatever the
/// page adds below (the desk: what it shows normally).
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
    @State private var setup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ScreenPreview(force: force, playlist: playlist, choices: choices, online: online > 0)
                VStack(alignment: .leading, spacing: 6) {
                    title
                    TimelineView(.periodic(from: .now, by: 15)) { _ in
                        Text(online > 0 ? screenStatus(force, playlist: playlist, choices: choices) : "This TV isn’t showing Flagcast yet.")
                            .font(.system(size: 13)).foregroundStyle(FC.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 6) {
                        if force?.isOn == true { Button("Back to Normal") { send(nil, 0) }.buttonStyle(GreenButton()) }
                        Button("Show Something Else…") { sending = true }.buttonStyle(force?.isOn == true ? AnyButtonStyle(PlainCardButton()) : AnyButtonStyle(GreenButton()))
                            .popover(isPresented: $sending, arrowEdge: .bottom) { SendNowPanel(target: name.isEmpty ? "this TV" : name, choices: choices) { send($0, $1) } }
                        if let url, online == 0 {
                            Button("Set Up This TV…") { setup = true }.buttonStyle(PlainCardButton())
                                .sheet(isPresented: $setup) { TVSetupSheet(name: name, url: url) }
                        }
                    }
                }
                Spacer(minLength: 0)
                if let url, online > 0 {
                    Menu { Button("Copy the TV’s Link") { copy(url.absoluteString) }; Button("Open It Here") { NSWorkspace.shared.open(url) } } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton).fixedSize().help("This TV’s link")
                }
            }
            details
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .raisedCard()
    }
}

/// A button style chosen at run time.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ s: S) { make = { AnyView(s.makeBody(configuration: $0)) } }
    func makeBody(configuration c: Configuration) -> some View { make(c) }
}

/// How to put Flagcast on a TV: three big steps and one button to copy the link.
struct TVSetupSheet: View {
    var name: String
    var url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Put Flagcast on \(name.isEmpty ? "this TV" : name)").font(FC.display(30))
            step(1, "Copy the TV’s link", "Send it to yourself (email or text) so you can open it on the TV.")
            HStack {
                Text(url.absoluteString).font(.system(size: 13).monospaced()).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(FC.paper2, in: RoundedRectangle(cornerRadius: 7))
                Button(copied ? "Copied" : "Copy the Link") { copy(url.absoluteString); copied = true }.buttonStyle(GreenButton())
            }
            step(2, "Open it in the TV’s web browser", "Or on the computer or stick plugged into the TV.")
            step(3, "Make it full screen", "This card turns green when the TV is showing Flagcast.")
            HStack { Button("Open It on This Mac") { NSWorkspace.shared.open(url) }; Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(24).frame(width: 520)
    }
    private func step(_ n: Int, _ t: String, _ sub: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(FC.display(22)).foregroundStyle(FC.onGreen).frame(width: 32, height: 32).background(FC.green, in: Circle())
            VStack(alignment: .leading, spacing: 2) { Text(t).font(.system(size: 15, weight: .semibold)); Text(sub).font(.callout).foregroundStyle(.secondary) }
        }
    }
}

/// Above the TVs: show something on every TV, or all the TVs in one place, and put them back to normal.
struct SendToManyBar: View {
    var groups: [String]
    var choices: PageChoices
    /// nil = every TV, else a place; page nil = back to normal
    var send: (String?, PageRef?, Int) -> Void
    @State private var target = "*"
    @State private var sending = false
    private var targetName: String { target == "*" ? "every TV" : "the TVs at \(target)" }

    var body: some View {
        HStack(spacing: 10) {
            Text("All at once:").font(.system(size: 14, weight: .bold))
            Picker("", selection: $target) {
                Text("Every TV").tag("*")
                if !groups.isEmpty { Divider(); ForEach(groups, id: \.self) { Text("TVs at \($0)").tag($0) } }
            }
            .labelsHidden().frame(width: 190)
            Spacer()
            Button("Back to Normal") { send(target == "*" ? nil : target, nil, 0) }.buttonStyle(PlainCardButton())
            Button("Show Something Else…") { sending = true }.buttonStyle(GreenButton())
                .popover(isPresented: $sending, arrowEdge: .bottom) { SendNowPanel(target: targetName, choices: choices) { send(target == "*" ? nil : target, $0, $1) } }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .raisedCard()
    }
}

// MARK: - the playlist (desk)

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
                Text("Pages, in order").font(.system(size: 12, weight: .semibold)).foregroundStyle(FC.muted)
                Spacer()
                if !others.isEmpty {
                    Menu("Copy to…") {
                        Button("Every Other TV") { copyTo(others.map(\.id)) }
                        Divider()
                        ForEach(others, id: \.id) { o in Button(o.name.isEmpty ? "Unnamed TV" : o.name) { copyTo([o.id]) } }
                    }
                    .fixedSize().controlSize(.small).disabled(playlist.isEmpty)
                }
            }
            if playlist.isEmpty { Text("Nothing picked: this TV shows everything in turn.").font(.callout).foregroundStyle(FC.muted) }
            ForEach(playlist.indices, id: \.self) { k in
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal").foregroundStyle(FC.muted).frame(width: 16).contentShape(Rectangle())
                        .draggable(String(k)).help("Drag to move")
                    Text("\(k + 1)").monospacedDigit().foregroundStyle(FC.muted).frame(width: 16)
                    PagePicker(page: $playlist[k], choices: choices)
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
                    Text("Goes round every \(playlist.reduce(0) { $0 + $1.secs }) seconds").font(.caption).foregroundStyle(FC.muted)
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
