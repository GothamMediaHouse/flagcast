import SwiftUI

// Switching the TVs (Show something else for a bit, to one TV, the TVs in one place or every TV) and a TV's own pages
// (Customize). The TV list, the TV page and Add a TV are in ClubTVs.swift (shared with the iPhone and iPad).

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
