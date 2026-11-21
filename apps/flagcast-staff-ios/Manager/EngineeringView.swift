import SwiftUI

/// Engineering (Flagcast Admin only, Admin → Screens & phones): every TV in one grid (TVs down, pages across: tap a
/// cell to switch that TV), tick several to switch them together, how long it lasts, and the take-over, players'
/// phones banner, announcement and scenes.
struct EngineeringPanel: View {
    var src: EngSource
    @State private var selected: Set<String> = []
    @State private var length: SendLength = .changed
    @State private var takeText = ""
    @State private var takeSecs = 25
    @State private var phoneText = ""
    @State private var flashText = ""
    @State private var sceneName = ""

    private var routes: [EngRoute] {
        var r = [EngRoute(id: "normal", title: "Normal", page: nil), EngRoute(id: "lb", title: "Board", page: PageRef(k: "lb"))]
        r += src.choices.flights.map { EngRoute(id: "lb-\($0)", title: "LB \($0)", page: PageRef(k: "lb", fl: $0)) }
        r.append(EngRoute(id: "p3", title: "Par 3s", page: PageRef(k: "p3")))
        r += src.choices.p3.map { EngRoute(id: "p3-\($0)", title: "Cam \($0)", page: PageRef(k: "p3", hole: $0)) }
        r += [("contests", "Contests"), ("skins", "Skins"), ("fund", "Fund"), ("sponsors", "Sponsors"), ("schedule", "Sched.")].map { EngRoute(id: $0.0, title: $0.1, page: PageRef(k: $0.0)) }
        r += src.choices.sponsors.map { EngRoute(id: "sp-\($0.id)", title: $0.name, page: PageRef(k: "sponsor", sponsor: $0.id)) }
        return r
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            controls
            grid
            box("Take over every TV") {
                if let t = src.take { HStack { Text("Now: \(t.kind)\(t.text.map { " · \($0)" } ?? "")").foregroundStyle(FC.red); Spacer(); Button("Clear") { take(["kind": "clear"]) } } }
                TextField("Message", text: $takeText).padding(10).background(FC.paper2, in: RoundedRectangle(cornerRadius: 9))
                Stepper("\(takeSecs) seconds", value: $takeSecs, in: 5...120, step: 5)
                HStack {
                    Button("Announce") { take(["kind": "msg", "text": takeText, "secs": takeSecs]) }.buttonStyle(GreenButton(full: true)).disabled(takeText.isEmpty)
                    Button("Hole in One!") { take(["kind": "ace", "text": takeText, "secs": takeSecs]) }.buttonStyle(PlainCardButton(full: true))
                }
                HStack {
                    if !src.choices.sponsors.isEmpty { Menu("Sponsor Moment") { ForEach(src.choices.sponsors, id: \.id) { s in Button(s.name) { take(["kind": "sponsor", "sponsor": s.id, "secs": takeSecs]) } } } }
                    Spacer()
                    if !src.replays.isEmpty { Menu("Replay") { ForEach(src.replays, id: \.id) { r in Button(r.label) { take(["kind": "replay", "replay": r.id]) } } } }
                }
                .font(.subheadline.weight(.semibold))
            }
            box("Players’ phones banner") {
                if let p = src.phone { HStack { Text("Now: \(src.choices.label(PageRef(k: p.k, fl: p.fl, hole: p.hole, sponsor: p.sponsor)))").foregroundStyle(FC.red); Spacer()
                    Button("Clear") { Task { await src.day("screen", ["display": "phones", "page": NSNull()], "Phones cleared.") } } } }
                TextField("Line on the banner", text: $phoneText).padding(10).background(FC.paper2, in: RoundedRectangle(cornerRadius: 9))
                Menu { ForEach(routes.filter { $0.page != nil }) { r in Button(r.title) { let t = phoneText; Task { await src.day("screen", ["display": "phones", "page": pageDict(r.page), "text": t], "On every player’s phone.") } } } }
                    label: { Text("Send to Phones…").frame(maxWidth: .infinity) }.buttonStyle(GreenButton(full: true))
            }
            box("Announcement") {
                if let f = src.announcement, !f.text.isEmpty { HStack { Text("“\(f.text)”").foregroundStyle(FC.muted); Spacer(); Button("Clear") { Task { await src.day("flash", ["text": ""], "Cleared.") } } } }
                HStack {
                    TextField("Shotgun start in 10 minutes", text: $flashText).padding(10).background(FC.paper2, in: RoundedRectangle(cornerRadius: 9))
                    Button("Show") { let t = flashText; Task { await src.day("flash", ["text": t], "On every TV."); flashText = "" } }.buttonStyle(GreenButton()).disabled(flashText.isEmpty)
                }
            }
            box("Scenes") {
                ForEach(src.scenes, id: \.id) { s in
                    HStack {
                        Text(s.name).fontWeight(src.currentScene == s.id ? .semibold : .regular)
                        if src.currentScene == s.id { Text("on now").font(.caption).foregroundStyle(FC.ok) }
                        Spacer()
                        Button("Put Back") { Task { await src.day("scene", ["apply": s.id], "Scene on.") } }
                        Button(role: .destructive) { Task { await src.day("scene", ["remove": s.id], "Scene deleted.") } } label: { Image(systemName: "trash") }
                    }
                }
                HStack {
                    TextField("Save what every TV shows now as…", text: $sceneName).padding(10).background(FC.paper2, in: RoundedRectangle(cornerRadius: 9))
                    Button("Save") { let n = sceneName; Task { await src.day("scene", ["save": n], "Scene saved."); sceneName = "" } }.buttonStyle(GreenButton()).disabled(sceneName.isEmpty)
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("How long", selection: $length) { ForEach(SendLength.allCases) { Text($0 == .changed ? "Until changed" : $0.title.replacingOccurrences(of: "For ", with: "")).tag($0) } }
                .pickerStyle(.segmented)
            HStack {
                Text(selected.isEmpty ? "Tap a cell to switch one TV, or tick TVs to switch several." : "\(selected.count) ticked").font(.footnote).foregroundStyle(FC.muted)
                Spacer()
            }
            HStack(spacing: 8) {
                Menu { ForEach(routes.filter { $0.page != nil }) { r in Button(r.title) { route(Array(selected), r) } } } label: { Text("Send to Ticked").frame(maxWidth: .infinity) }
                    .buttonStyle(GreenButton(full: true)).disabled(selected.isEmpty)
                Button("Ticked to Normal") { route(Array(selected), routes[0]) }.buttonStyle(PlainCardButton(full: true)).disabled(selected.isEmpty)
            }
            Button("Every TV Back to Normal") { send("*", nil, to: "every TV") }.buttonStyle(PlainCardButton(full: true))
        }
        .card()
    }

    private var grid: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    Text("").frame(width: 34)
                    Text("TV").frame(width: 130, alignment: .leading)
                    Text("NOW").frame(width: 120, alignment: .leading)
                    ForEach(routes) { r in Text(r.title.uppercased()).lineLimit(1).frame(width: 62) }
                }
                .font(.system(size: 10, weight: .bold)).foregroundStyle(FC.onGreen).frame(height: 32).background(FC.green)
                ForEach(src.tvs) { t in
                    GridRow {
                        Button { if selected.contains(t.id) { selected.remove(t.id) } else { selected.insert(t.id) } } label: {
                            Image(systemName: selected.contains(t.id) ? "checkmark.square.fill" : "square").foregroundStyle(FC.primary)
                        }
                        .frame(width: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) { Circle().fill(t.online > 0 ? FC.ok : FC.muted.opacity(0.4)).frame(width: 7, height: 7); Text(t.name.isEmpty ? "TV" : t.name).font(.system(size: 13, weight: .semibold)).lineLimit(1) }
                            Text("\(t.id) · \(t.online) open\(t.place.isEmpty ? "" : " · \(t.place)")").font(.system(size: 9).monospaced()).foregroundStyle(FC.muted).lineLimit(1)
                        }
                        .frame(width: 130, alignment: .leading)
                        TimelineView(.periodic(from: .now, by: 10)) { _ in
                            if let f = t.force, f.isOn {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(src.choices.label(f)).font(.system(size: 11, weight: .semibold)).foregroundStyle(FC.red).lineLimit(1)
                                    Text(f.until > 0 ? "\(max(1, Int((f.until / 1000 - Date().timeIntervalSince1970) / 60 + 0.99))) min left" : "no end").font(.system(size: 9)).foregroundStyle(FC.muted)
                                }
                            } else { Text("Normal").font(.system(size: 11)).foregroundStyle(FC.muted) }
                        }
                        .frame(width: 120, alignment: .leading)
                        ForEach(routes) { r in
                            let on = r.matches(t.force)
                            Button { route([t.id], r) } label: {
                                RoundedRectangle(cornerRadius: 6).fill(on ? (r.page == nil ? FC.ok : FC.red) : FC.paper2.opacity(0.7)).frame(width: 50, height: 30)
                                    .overlay { if on { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) } }
                                    .frame(width: 62, height: 46)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(selected.contains(t.id) ? FC.paper2.opacity(0.6) : .clear)
                    .overlay(alignment: .bottom) { Rectangle().fill(FC.hairline).frame(height: 1) }
                }
                if src.tvs.isEmpty { GridRow { Text("No TVs yet.").foregroundStyle(FC.muted).padding(14).gridCellColumns(3 + routes.count) } }
            }
            .padding(.leading, 4)
        }
        .background(FC.card).clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func box<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { CardTitle(title); c() }.card()
    }
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
    private func take(_ b: [String: Any]) { Task { await src.day("take", b, b["kind"] as? String == "clear" ? "Back to normal." : "On every TV now.") } }
}
