import SwiftUI
import MapKit
import UniformTypeIdentifiers
import CoreImage.CIFilterBuiltins

// The Mac's other sections for iPhone and iPad: Report, Course map, Where the groups are, and the cart cards and
// hole-in-one log on Links. Same data and the same day-of calls as the Mac ("map", "groups", "ace").

private func coord(_ p: GeoPoint) -> CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng) }

// MARK: - Report

struct ReportView: View {
    var body: some View { WithTournament { ReportPage(doc: $0) } }
}

private struct ReportPage: View {
    @Bindable var doc: DeskDoc
    @State private var file: ReportCSV?

    var body: some View {
        CardPage(image: doc.picture.image, kicker: doc.ev.name, title: "Report", sub: "Results, sponsors and GHIN posting") {
            CardBox(title: "Download", footer: "The GHIN file has each player’s GHIN number, tees, rating and slope, hole-by-hole scores and the adjusted gross score (each hole capped at net double bogey), ready for the club’s handicap chair. Scramble scores can’t be posted for handicaps.") {
                VStack(spacing: 8) {
                    Button { export("results", results()) } label: { Label("Results", systemImage: "list.number") }.buttonStyle(GreenButton(full: true))
                    Button { export("sponsors", sponsors()) } label: { Label("Sponsor Report", systemImage: "star") }.buttonStyle(PlainCardButton(full: true))
                    Button { if let r = ghin() { export("ghin-posting", r) } } label: { Label("Scores for GHIN Posting", systemImage: "doc.text") }.buttonStyle(PlainCardButton(full: true))
                    Text("Each one is a spreadsheet file (CSV) you can open in Numbers or Excel.").font(.footnote).foregroundStyle(FC.muted).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
            }
            CardBox(title: "Sponsors", footer: "Screen time counts every minute a sponsor was on a TV. Phone views count each time a golfer saw it; taps count opens of its link.") {
                if doc.ev.sponsors.isEmpty { Text("No sponsors.").foregroundStyle(FC.muted).padding(14) }
                ForEach(doc.ev.sponsors) { s in
                    let st = doc.ev.stats[s.id]
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.name.isEmpty ? "Sponsor" : s.name).font(.system(size: 16, weight: .semibold))
                        Text(sponsorSpotName(s.spot) + (s.holes.isEmpty ? "" : " · " + s.holes.map(String.init).joined(separator: ", "))).font(.footnote).foregroundStyle(FC.muted)
                        HStack(spacing: 16) {
                            stat("\(Int((st?.secs ?? 0) / 60)) min", "on the TVs")
                            stat("\(Int(st?.view ?? 0))", "phone views")
                            stat("\(Int(st?.tap ?? 0))", "taps")
                        }
                        .padding(.top, 2)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) { Rectangle().fill(FC.hairline).frame(height: 1).padding(.leading, 14) }
                }
            }
            CardBox(title: "Score changes by staff") {
                if doc.ev.log.isEmpty { Text("None.").foregroundStyle(FC.muted).padding(14) }
                ForEach(Array(doc.ev.log.reversed().enumerated()), id: \.offset) { _, l in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(Date(timeIntervalSince1970: l.at / 1000).formatted(date: .omitted, time: .shortened)).monospacedDigit().foregroundStyle(FC.muted).frame(width: 70, alignment: .leading)
                        Text("\(l.by): \(l.player) (\(l.team)), hole \(l.h): \(l.from.map(String.init) ?? "–") → \(l.to.map(String.init) ?? "removed")")
                    }
                    .font(.subheadline).padding(.horizontal, 14).padding(.vertical, 8)
                }
            }
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { Task { await doc.refreshDay() } } label: { Label("Refresh", systemImage: "arrow.clockwise") } } }
        .task { await doc.refreshDay() }
        .fileExporter(isPresented: Binding(get: { file != nil }, set: { if !$0 { file = nil } }), document: file, contentType: .commaSeparatedText, defaultFilename: file?.name) { _ in file = nil }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 0) { Text(v).font(.system(size: 17, weight: .bold)).monospacedDigit(); Text(l).font(.caption).foregroundStyle(FC.muted) }
    }
    private func export(_ what: String, _ rows: [[String]]) {
        if rows.count <= 1 { doc.flash("Nothing to download yet."); return }
        file = ReportCSV(name: "\(doc.ev.name.isEmpty ? "Tournament" : doc.ev.name.replacingOccurrences(of: "/", with: "-")) - \(what).csv", rows: rows)
    }
    private func results() -> [[String]] {
        guard let live = doc.live else { return [] }
        if live.format.isMatch { return Core.matchRows(live) }
        let flights: [String?] = live.flights.isEmpty ? [nil] : live.flights
        // multi-day: each round's score and the total, then this round's holes
        let tot = Core.showsTotal(live), rn = tot ? Core.roundCount(live) : 0
        var rows = [["Flight", "Pos", "Team", "Players", "Thru", tot ? "Total" : "Score"] + (0..<rn).map { "R\($0 + 1)" } + live.course.holes.map { "H\($0.n)" }]
        for fl in flights {
            for l in Core.board(live, live.scores, flight: fl) {
                rows.append([fl ?? "", l.pos, l.name, l.sub, l.thru, l.played > 0 ? String(l.score) : ""] + (0..<rn).map { i in i < l.rounds.count ? l.rounds[i].map { String($0.score) } ?? "" : "" }
                    + l.card.map { r in r.done ? ((live.format.show == "gross" ? r.gross : r.net).map(String.init) ?? "") : "" })
            }
        }
        return rows
    }
    private func sponsors() -> [[String]] {
        [["Sponsor", "Where", "Holes", "Screen minutes", "Phone views", "Taps"]] + doc.ev.sponsors.map { s in
            let st = doc.ev.stats[s.id]
            return [s.name, sponsorSpotName(s.spot), s.holes.map(String.init).joined(separator: " "), "\(Int((st?.secs ?? 0) / 60))", "\(Int(st?.view ?? 0))", "\(Int(st?.tap ?? 0))"]
        }
    }
    /// the Mac's GHIN posting file, the same columns and caps
    private func ghin() -> [[String]]? {
        guard let live = doc.live else { return nil }
        if doc.ev.format.isScramble { doc.flash("Scramble scores can’t be posted for handicaps."); return nil }
        let H = doc.ev.course.holes, par = doc.ev.course.par, T = doc.ev.course.tees
        var rows = [["Player", "GHIN number", "Handicap Index", "Course handicap", "Date", "Course", "Tees", "Course rating", "Slope", "Par"] + H.map { "H\($0.n)" } + ["Holes played", "Gross", "Adjusted gross", "Picked up on", "Team"]]
        for t in doc.ev.teams { for p in t.players {
            let arr = live.scores[t.id]?[p.id] ?? []
            let tee = T.first { $0.id == p.tee } ?? (p.index != nil ? T.first : nil)
            var gross = 0, adj = 0, n = 0, pu: [Int] = []
            let holes: [String] = H.enumerated().map { i, h in
                guard i < arr.count, let v = arr[i] else { return "" }
                let cap = h.par + 2 + max(0, Core.strokesOn(Int(p.hcp), h.hcp)); n += 1
                if v == 0 { pu.append(h.n); adj += cap; return String(cap) }
                gross += v; adj += min(v, cap); return String(v)
            }
            if n == 0 { continue }
            rows.append([p.name, p.ghin, Core.fmtIndex(p.index), "\(Int(p.hcp))", doc.ev.date, doc.ev.course.name.isEmpty ? doc.ev.club : doc.ev.course.name,
                         tee?.name ?? "", tee.map { String($0.rating) } ?? "", tee.map { String(Int($0.slope)) } ?? "", "\(tee.map { $0.par > 0 ? $0.par : par } ?? par)"]
                        + holes + ["\(n)", pu.isEmpty ? "\(gross)" : "", "\(adj)", pu.map(String.init).joined(separator: " "), t.name])
        } }
        if rows.count == 1 { doc.flash("No scores yet."); return nil }
        return rows
    }
}

struct ReportCSV: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var name: String, rows: [[String]]
    init(name: String, rows: [[String]]) { self.name = name; self.rows = rows }
    init(configuration: ReadConfiguration) throws { name = ""; rows = [] }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let text = rows.map { $0.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ",") }.joined(separator: "\r\n")
        return FileWrapper(regularFileWithContents: Data(("\u{FEFF}" + text).utf8))
    }
}

// MARK: - Course map

/// The course map for hole GPS on Apple's satellite pictures: pick a hole, then tap the tee and the front, middle and
/// back of the green. It saves as you go, and the club keeps it for its next tournament. (Hazards: on the Mac.)
struct CourseMapScreen: View {
    var body: some View { WithTournament { CourseMapPage(doc: $0) } }
}

private struct CourseMapPage: View {
    @Bindable var doc: DeskDoc
    @Environment(\.horizontalSizeClass) private var size
    @State private var hole = 1
    @State private var tool: Spot? = .tee
    @State private var camera: MapCameraPosition = .automatic
    @AppStorage("map.3d") private var threeD = false
    @State private var saveTask: Task<Void, Never>?
    @State private var saving = false

    enum Spot: String, CaseIterable, Identifiable {
        case tee, f, m, b
        var id: String { rawValue }
        var title: String { switch self { case .tee: "Tee"; case .f: "Front"; case .m: "Middle"; case .b: "Back" } }
        var label: String { switch self { case .tee: "tee"; case .f: "front of the green"; case .m: "middle of the green"; case .b: "back of the green" } }
    }
    private var h: HoleMap { doc.ev.map.holes[hole] ?? HoleMap() }
    private func set(_ f: (inout HoleMap) -> Void) { var x = h; f(&x); doc.ev.map.holes[hole] = x; scheduleSave() }

    var body: some View {
        VStack(spacing: 0) {
            header
            holeStrip
            if size == .regular {
                HStack(spacing: 0) { map; panel.frame(width: 320).background(FC.paper) }
            } else {
                map
                panel.background(FC.paper)
            }
        }
        .background(FC.paper)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(FC.green, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar).toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { hole = firstOpenHole(); pick(hole); fit() }
        .onChange(of: hole) { _, _ in fit() }
        .onChange(of: threeD) { _, _ in fit() }
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Course map").font(FC.display(32))
                Text(doc.ev.course.name.isEmpty ? doc.ev.name : doc.ev.course.name).font(.footnote).foregroundStyle(FC.onGreenMuted).lineLimit(1)
            }
            Spacer()
            Text(saving ? "Saving…" : "Saves as you go").font(.caption.weight(.semibold)).foregroundStyle(FC.onGreenMuted)
            Toggle(isOn: $threeD) { Label("3D", systemImage: "cube") }.toggleStyle(.button).buttonStyle(GlassButton())
        }
        .foregroundStyle(.white).padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 10).background(FC.green)
    }

    private var holeStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(doc.ev.course.holes, id: \.n) { x in
                    let o = doc.ev.map.holes[x.n], done = o?.tee != nil && (o?.m ?? o?.f) != nil
                    Button { pick(x.n) } label: {
                        VStack(spacing: 0) { Text("\(x.n)").font(.callout.bold()); Text("par \(x.par)").font(.caption2).opacity(0.7) }
                            .frame(width: 44, height: 38)
                            .foregroundStyle(x.n == hole ? FC.green : .white)
                            .background(x.n == hole ? FC.onGreen : done ? Color.white.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(alignment: .topTrailing) { if done { Image(systemName: "checkmark.circle.fill").font(.system(size: 9)).foregroundStyle(FC.flag).offset(x: -2, y: 2) } }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hole \(x.n)\(done ? ", mapped" : "")")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .background(FC.green)
    }

    private var map: some View {
        MapReader { proxy in
            Map(position: $camera, interactionModes: .all) {
                ForEach(doc.ev.map.holes.keys.sorted().filter { $0 != hole }, id: \.self) { n in
                    if let o = doc.ev.map.holes[n], let g = o.m ?? o.f {
                        Annotation("", coordinate: coord(g)) {
                            Button { pick(n) } label: { Text("\(n)").font(.caption2.bold()).padding(4).background(.black.opacity(0.55), in: Circle()).foregroundStyle(.white) }.buttonStyle(.plain)
                        }
                    }
                }
                if let t = h.tee, let g = h.m ?? h.f { MapPolyline(coordinates: ([t] + h.line + [g]).map(coord)).stroke(.white.opacity(0.85), lineWidth: 2) }
                ForEach(h.hz, id: \.id) { z in
                    Annotation("", coordinate: coord(z.p)) { Circle().fill(z.k == "water" ? Color.blue : Color(red: 0.95, green: 0.89, blue: 0.69)).frame(width: 12, height: 12).overlay(Circle().stroke(.black.opacity(0.5))) }
                }
                if let p = h.tee { Annotation("", coordinate: coord(p)) { pin("T", FC.flag, .black) } }
                if let p = h.f { Annotation("", coordinate: coord(p)) { pin("F", .white, .black) } }
                if let p = h.b { Annotation("", coordinate: coord(p)) { pin("B", .white, .black) } }
                if let p = h.m { Annotation("", coordinate: coord(p)) { pin("⚑", .red, .white) } }
                UserAnnotation()
            }
            .mapStyle(.imagery(elevation: threeD ? .realistic : .flat))
            .mapControls { MapCompass(); MapScaleView(); MapPitchToggle() }
            .onTapGesture { pt in
                guard tool != nil, let c = proxy.convert(pt, from: .local) else { return }
                place(GeoPoint(lat: c.latitude, lng: c.longitude))
            }
            .overlay(alignment: .top) {
                Text(tool.map { "Tap the map to set the \($0.label)." } ?? "Pick what to set below, then tap the map.")
                    .font(.callout.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 6).background(.regularMaterial, in: Capsule()).padding(10)
            }
        }
    }

    private func pin(_ t: String, _ fill: Color, _ ink: Color) -> some View {
        Text(t).font(.system(size: 12, weight: .heavy)).foregroundStyle(ink).frame(width: 26, height: 26)
            .background(fill, in: Circle()).overlay(Circle().stroke(.black.opacity(0.6), lineWidth: 1.5)).shadow(radius: 2)
    }

    private var panel: some View {
        let par = doc.ev.course.holes.first { $0.n == hole }?.par ?? 4
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Hole \(hole) · par \(par)").font(FC.display(26))
                Picker("Set", selection: $tool) {
                    ForEach(Spot.allCases) { s in Text(s.title).tag(Spot?.some(s)) }
                }
                .pickerStyle(.segmented)
                HStack(spacing: 10) {
                    ForEach(Spot.allCases) { s in
                        let set = point(s) != nil
                        Label(s.title, systemImage: set ? "checkmark.circle.fill" : "circle").font(.caption).foregroundStyle(set ? FC.ok : FC.muted)
                    }
                }
                if let t = h.tee, let g = h.m ?? h.f { LabeledContent("Tee to the middle", value: "\(yards(t, g)) yds") }
                if let f = h.f, let b = h.b { LabeledContent("Green depth", value: "\(yards(f, b)) yds") }
                HStack(spacing: 8) {
                    Button("Show the Hole") { fit() }.buttonStyle(PlainCardButton(full: true))
                    Button("Clear This Hole", role: .destructive) { doc.ev.map.holes[hole] = nil; tool = .tee; scheduleSave() }.buttonStyle(PlainCardButton(full: true))
                }
                Help("Golfers’ phones use these spots for the yardages to the green. Bunkers and water are added in Flagcast Manager on the Mac.")
            }
            .font(.subheadline)
            .padding(16)
        }
        .frame(maxHeight: size == .regular ? .infinity : 260)
    }

    private func point(_ s: Spot) -> GeoPoint? { switch s { case .tee: h.tee; case .f: h.f; case .m: h.m; case .b: h.b } }
    private func place(_ p: GeoPoint) {
        guard let tool else { return }
        switch tool { case .tee: set { $0.tee = p }; case .f: set { $0.f = p }; case .m: set { $0.m = p }; case .b: set { $0.b = p } }
        let x = h   // the next thing still missing on this hole
        self.tool = x.tee == nil ? .tee : x.f == nil ? .f : x.m == nil ? .m : x.b == nil ? .b : tool
    }
    private func pick(_ n: Int) {
        hole = n
        let x = doc.ev.map.holes[n] ?? HoleMap()
        tool = x.tee == nil ? .tee : x.f == nil ? .f : x.m == nil ? .m : x.b == nil ? .b : .m
    }
    private func firstOpenHole() -> Int { doc.ev.course.holes.map(\.n).first { n in let x = doc.ev.map.holes[n]; return x?.tee == nil || (x?.m ?? x?.f) == nil } ?? 1 }

    /// Frame the hole with the green at the top (or the course, or the club's spot).
    private func fit() {
        let x = h, pts = ([x.tee, x.f, x.m, x.b] + x.hz.flatMap { [$0.p, $0.c] }).compactMap { $0 }
        if let t = x.tee, let g = x.m ?? x.f {
            let mid = GeoPoint(lat: (t.lat + g.lat) / 2, lng: (t.lng + g.lng) / 2)
            withAnimation { camera = .camera(MapCamera(centerCoordinate: coord(mid), distance: max(350, Double(yards(t, g)) / 1.0936 * 2.6), heading: bearing(t, g), pitch: threeD ? 55 : 0)) }
        } else if let p = pts.first {
            withAnimation { camera = .camera(MapCamera(centerCoordinate: coord(p), distance: 600, heading: 0, pitch: threeD ? 55 : 0)) }
        } else if let any = doc.ev.map.holes.values.compactMap({ $0.m ?? $0.tee }).first {
            withAnimation { camera = .camera(MapCamera(centerCoordinate: coord(any), distance: 2500, heading: 0, pitch: 0)) }
        } else if let at = doc.ev.course.at {
            withAnimation { camera = .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: at.lat, longitude: at.lng), distance: 2500, heading: 0, pitch: 0)) }
        }
    }
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            if Task.isCancelled { return }
            saving = true; defer { saving = false }
            guard let map = try? Net.object(doc.ev.map) else { return }
            await doc.day("map", ["map": map])
        }
    }
}

// MARK: - Where the groups are

/// Each scorecard with GPS on sends its spot during the tournament (the Mac's "groups" call), every 20 seconds.
struct GroupsScreen: View {
    var body: some View { WithTournament { GroupsPage(doc: $0) } }
}

private struct GroupsPage: View {
    @Bindable var doc: DeskDoc
    @Environment(\.horizontalSizeClass) private var size
    @State private var groups: [Spot] = []
    @State private var on = true
    @State private var camera: MapCameraPosition = .automatic
    @State private var picked: String?

    struct Spot: Identifiable, Hashable { var id: String; var name: String; var start: Int; var hole: Int; var at: GeoPoint; var t: Double; var since: Double = 0; var sample = false
        var card: GroupCardSpot { GroupCardSpot(id: id, name: name, start: start, hole: hole, t: t, since: since, sample: sample) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Where the groups are").font(FC.display(32)).lineLimit(1).minimumScaleFactor(0.6)
                    Text("\(groups.count) group\(groups.count == 1 ? "" : "s") on the course").font(.footnote).foregroundStyle(FC.onGreenMuted)
                }
                Spacer()
            }
            .foregroundStyle(.white).padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 10).background(FC.green)
            if size == .regular {
                HStack(spacing: 0) { map; list.frame(width: 320) }
            } else {
                map
                list.frame(maxHeight: picked == nil ? 280 : 480)
            }
        }
        .background(FC.paper)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(FC.green, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar).toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    private var map: some View {
        Map(position: $camera) {
            ForEach(doc.ev.map.holes.keys.sorted(), id: \.self) { n in
                if let g = doc.ev.map.holes[n]?.m { Annotation("", coordinate: coord(g)) { Text("\(n)").font(.caption2.bold()).padding(3).background(.black.opacity(0.5), in: Circle()).foregroundStyle(.white) } }
            }
            ForEach(groups) { g in
                Annotation(g.name, coordinate: coord(g.at)) {
                    Text(g.hole > 0 ? "\(g.hole)" : "•").font(.caption.bold()).frame(minWidth: 26, minHeight: 26).padding(.horizontal, 4)
                        .background(stale(g) ? Color.gray : FC.blue, in: Capsule()).overlay(Capsule().stroke(.white, lineWidth: picked == g.id ? 3 : 2)).foregroundStyle(.white)
                        .onTapGesture { pick(g) }
                }
            }
        }
        .mapStyle(.imagery(elevation: .flat))
        .mapControls { MapCompass(); MapScaleView() }
        .overlay(alignment: .top) {
            if !on { Text("Groups show here only during the tournament: on its date, until the results are locked.").font(.callout).padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding() }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let g = groups.first(where: { $0.id == picked }) {
                    GroupCard(doc: doc, group: g.card) { picked = nil }.padding(12)
                }
                if groups.isEmpty { Text("No groups yet. They show up when a scorecard has GPS on.").font(.subheadline).foregroundStyle(FC.muted).padding(16) }
                ForEach(groups) { g in
                    Button { pick(g) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(FC.ink)
                            Text("\(g.hole > 0 ? "On hole \(g.hole)" : "On the course") · thru \(thru(g.id)) · started on \(g.start) · \(ago(g.t))").font(.footnote).foregroundStyle(FC.muted)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(picked == g.id ? FC.paper2 : .clear).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) { Rectangle().fill(FC.hairline).frame(height: 1) }
                }
                GolferNotesToggle(doc: doc).padding(16)
            }
        }
        .background(FC.card)
    }

    private func pick(_ g: Spot) {
        picked = g.id
        withAnimation { camera = .camera(MapCamera(centerCoordinate: coord(g.at), distance: 500, heading: 0, pitch: 0)) }
    }
    private func load() async {
        guard let r = await doc.day("groups") else { return }
        on = r["on"] as? Bool ?? false
        let now = r["now"] as? Double ?? Date().timeIntervalSince1970 * 1000
        groups = (r["groups"] as? [[String: Any]] ?? []).compactMap { g in
            guard let at = g["at"] as? [Double], at.count == 2 else { return nil }
            return Spot(id: g["team"] as? String ?? UUID().uuidString, name: g["name"] as? String ?? "Group", start: g["start"] as? Int ?? 1, hole: g["hole"] as? Int ?? 0,
                        at: GeoPoint(lat: at[0], lng: at[1]), t: (g["t"] as? Double ?? now) - now + Date().timeIntervalSince1970 * 1000,
                        since: (g["since"] as? Double).map { $0 - now + Date().timeIntervalSince1970 * 1000 } ?? 0, sample: g["sample"] as? Bool ?? false)
        }
        if camera == .automatic, let first = groups.first { camera = .camera(MapCamera(centerCoordinate: coord(first.at), distance: 2500, heading: 0, pitch: 0)) }
        else if camera == .automatic, let any = doc.ev.map.holes.values.compactMap({ $0.m }).first { camera = .camera(MapCamera(centerCoordinate: coord(any), distance: 2500, heading: 0, pitch: 0)) }
    }
    private func stale(_ g: Spot) -> Bool { Date().timeIntervalSince1970 * 1000 - g.t > 10 * 60_000 }
    private func ago(_ t: Double) -> String { let m = Int((Date().timeIntervalSince1970 * 1000 - t) / 60_000); return m < 1 ? "just now" : "\(m) min ago" }
    private func thru(_ team: String) -> String {
        let s = doc.live?.scores[team] ?? [:]
        return "\((0..<18).filter { i in !s.isEmpty && s.values.allSatisfy { i < $0.count && $0[i] != nil } }.count)"
    }
}

// MARK: - cart cards and the hole-in-one log (Links)

/// A QR code for a link (Core Image, no network).
private enum QRCode {
    static func image(_ s: String, scale: CGFloat = 8) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(s.utf8); f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// One card per team with its QR code: players scan it to open their scorecard (the Mac's card, the same words).
private struct CartCardView: View {
    let team: DeskTeam, title: String, date: String, url: URL
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title + (date.isEmpty ? "" : " · \(date)")).font(.system(size: 10, weight: .semibold)).textCase(.uppercase).foregroundStyle(.gray)
                Text(team.displayName.isEmpty ? "Team" : team.displayName).font(.system(size: 22, weight: .heavy))
                Text("Start: hole \(team.start)" + (team.flight.isEmpty ? "" : " · Flight \(team.flight)")).font(.system(size: 12, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) { ForEach(team.players) { Text($0.name).font(.system(size: 12)) } }
                Spacer(minLength: 6)
                (Text("Keep score on your phone. ").bold() + Text("Point your camera at the code and tap the link. No app, no sign-in. One person per cart keeps score, and the leaderboard and big screens update as you play."))
                    .font(.system(size: 10)).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 6) {
                if let img = QRCode.image(url.absoluteString) { Image(uiImage: img).interpolation(.none).resizable().frame(width: 150, height: 150) }
                Text(team.code).font(.system(size: 18, weight: .bold, design: .monospaced))
            }
        }
        .foregroundStyle(.black)
        .padding(22)
        .frame(width: 520, height: 330, alignment: .topLeading)
        .background(.white)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4])).foregroundStyle(.gray.opacity(0.6)))
    }
}

/// Big print: one card a page, the cart number, team and start hole large enough to read from the seat of a cart.
private struct BigCartCardView: View {
    let team: DeskTeam, title: String, date: String, url: URL
    var body: some View {
        VStack(spacing: 18) {
            Text(title + (date.isEmpty ? "" : " · \(date)")).font(.system(size: 14, weight: .semibold)).textCase(.uppercase).foregroundStyle(.gray)
            Text("CART").font(.system(size: 18, weight: .bold, design: .monospaced)).tracking(6).foregroundStyle(.gray)
            Text(team.cart.isEmpty ? "–" : team.cart).font(.system(size: 150, weight: .heavy)).minimumScaleFactor(0.4).lineLimit(1)
            Text(team.displayName.isEmpty ? "Team" : team.displayName).font(.system(size: 40, weight: .heavy)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.5)
            Text("Start on hole \(team.start)" + (team.flight.isEmpty ? "" : " · Flight \(team.flight)")).font(.system(size: 30, weight: .bold))
            if let img = QRCode.image(url.absoluteString) { Image(uiImage: img).interpolation(.none).resizable().frame(width: 220, height: 220) }
            Text(team.code).font(.system(size: 28, weight: .bold, design: .monospaced))
            Text("Point your phone’s camera at the code to keep score. No app, no sign-in.").font(.system(size: 16)).multilineTextAlignment(.center)
        }
        .foregroundStyle(.black).padding(40).frame(width: 612, height: 792).background(.white)
    }
}

struct CartCardsBox: View {
    let doc: DeskDoc
    @State private var big = false
    @State private var pdf: URL?
    private var teams: [DeskTeam] { doc.ev.teams.filter { !$0.code.isEmpty }.sorted { ($0.start, $0.displayName) < ($1.start, $1.displayName) } }
    private var title: String { doc.ev.screens.title.isEmpty ? doc.ev.name : doc.ev.screens.title }

    var body: some View {
        CardBox(title: "Cart cards", footer: teams.isEmpty ? (doc.dirty ? "Save first: new teams get their codes when you save." : "Add teams on the Teams page and save.") : nil) {
            VStack(alignment: .leading, spacing: 12) {
                Text("One card per team with its QR code. Players scan it to open their scorecard: no app to download.").font(.subheadline).foregroundStyle(FC.muted)
                Toggle("Big print (one card a page, large cart number)", isOn: $big).tint(FC.primary).font(.subheadline)
                Button { printCards() } label: { Label("Print \(teams.count) Cart Card\(teams.count == 1 ? "" : "s")…", systemImage: "printer") }
                    .buttonStyle(GreenButton(full: true)).disabled(teams.isEmpty)
                if let pdf { ShareLink(item: pdf) { Label("Save or Send the Cards (PDF)", systemImage: "square.and.arrow.up") }.buttonStyle(PlainCardButton(full: true)) }
            }
            .padding(14)
        }
        .onChange(of: big) { _, _ in pdf = nil }
    }

    /// Two cards to a US Letter page (or one, big), as a PDF, then the print sheet (or Save to Files).
    @MainActor private func printCards() {
        let per = big ? 1 : 2, page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let pages = stride(from: 0, to: teams.count, by: per).map { Array(teams[$0..<min($0 + per, teams.count)]) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(title.isEmpty ? "Tournament" : title.replacingOccurrences(of: "/", with: "-")) cart cards.pdf")
        var box = page
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { doc.flash("The cards couldn’t be made."); return }
        for set in pages {
            let content = Group {
                if big { BigCartCardView(team: set[0], title: title, date: doc.ev.date, url: doc.cartURL(set[0].code)) }
                else {
                    VStack(spacing: 40) { ForEach(set) { CartCardView(team: $0, title: title, date: doc.ev.date, url: doc.cartURL($0.code)) } }
                        .frame(width: page.width, height: page.height).background(.white)
                }
            }
            .environment(\.colorScheme, .light)
            let r = ImageRenderer(content: content)
            r.proposedSize = ProposedViewSize(page.size)
            ctx.beginPDFPage(nil)
            r.render { size, draw in
                ctx.translateBy(x: (page.width - size.width) / 2, y: (page.height - size.height) / 2)
                draw(ctx)
            }
            ctx.endPDFPage()
        }
        ctx.closePDF()
        pdf = url
        let p = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil); info.outputType = .general; info.jobName = "\(title) cart cards"
        p.printInfo = info; p.printingItem = url
        p.present(animated: true)
    }
}

/// Holes in one golfers reported, with Remove for one entered by mistake (the Mac's "ace" call).
struct AcesBox: View {
    let doc: DeskDoc
    var body: some View {
        let aces = doc.live?.aces ?? doc.ev.aces
        CardBox(title: "Hole-in-one log") {
            if aces.isEmpty { Text("None yet.").font(.subheadline).foregroundStyle(FC.muted).padding(14) }
            ForEach(aces, id: \.self) { a in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Hole \(a.hole): \(a.name)").font(.system(size: 15, weight: .semibold))
                        Text("\(a.team) · \(Date(timeIntervalSince1970: a.at / 1000).formatted(date: .omitted, time: .shortened))").font(.footnote).foregroundStyle(FC.muted)
                    }
                    Spacer()
                    Menu { Button("Remove (Entered by Mistake)", role: .destructive) { Task { await doc.day("ace", ["remove": a.at], done: "Removed.") } } } label: { Image(systemName: "ellipsis.circle").foregroundStyle(FC.link) }
                }
                .padding(.horizontal, 14).frame(minHeight: 54)
                .overlay(alignment: .bottom) { Rectangle().fill(FC.hairline).frame(height: 1).padding(.leading, 14) }
            }
        }
    }
}
