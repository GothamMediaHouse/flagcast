import SwiftUI


/// Staff and playlists: golf pros' and marshals' PINs, the club's screens and what each plays, and the schedule.
struct StaffView: View {
    @Bindable var doc: DeskDoc
    @Environment(DeskNav.self) private var nav

    var body: some View {
        DeskPage(doc: doc, section: .staff) {
            EmptyView()
        } title: {
            HeroTitle(title: "Staff", size: 52, sub: "Golf pros, marshals, screens and the schedule", subBeside: true)
        } content: {
            CardForm {
            SwiftUI.Section {
                LabeledContent("Tournament code") { Text(doc.id.uppercased()).font(.title3.monospaced().weight(.semibold)).textSelection(.enabled) }
                ForEach($doc.ev.pins) { $p in
                    HStack {
                        Image(systemName: p.role == "marshal" ? "flag" : "person.badge.key").foregroundStyle(.secondary).frame(width: 20)
                        TextField("Name", text: $p.name)
                        Picker("", selection: $p.role) { Text("Golf pro").tag("pro"); Text("Marshal").tag("marshal") }.labelsHidden().frame(width: 110)
                        TextField("PIN", text: Binding(get: { p.pin }, set: { p.pin = String($0.filter(\.isNumber).prefix(8)) })).font(.body.monospaced()).frame(width: 90)
                        Button(role: .destructive) { doc.ev.pins.removeAll { $0.id == p.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
                HStack {
                    Button { addPin("pro") } label: { Label("Add Golf Pro", systemImage: "plus") }
                    Button { addPin("marshal") } label: { Label("Add Marshal", systemImage: "plus") }
                }
            } header: { Text("Golf pros and marshals") } footer: {
                Help("They sign in to the Flagcast phone app with the tournament code and their PIN (4 to 8 digits). A golf pro can fix scores, switch screens, take over the screens and nudge a cart. A marshal can only post contest results.")
            }
            SwiftUI.Section {
                HStack {
                    Text(doc.ev.displays.isEmpty ? "No TVs yet." : "\(doc.ev.displays.count) TV\(doc.ev.displays.count == 1 ? "" : "s"): \(doc.ev.displays.map(\.name).joined(separator: ", "))")
                        .foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button("Go to Screens") { nav.section = .screens }
                }
            } header: { Text("TVs at the club") } footer: {
                Help("The club’s TVs and what they show are on the Screens page.")
            }
            SwiftUI.Section {
                ForEach($doc.ev.schedule.indices, id: \.self) { i in
                    HStack {
                        TextField("Time", text: $doc.ev.schedule[i].time, prompt: Text("8:00 AM")).frame(width: 110)
                        TextField("What", text: $doc.ev.schedule[i].what, prompt: Text("Shotgun start"))
                        Button(role: .destructive) { doc.ev.schedule.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
                Button { doc.ev.schedule.append(ScheduleItem()) } label: { Label("Add a Time", systemImage: "plus") }
            } header: { Text("Schedule") } footer: { Help("Shows on the Schedule page of the screens.") }
        }
            }
    }
    private func addPin(_ role: String) {
        let pin = StaffPin.newPin(doc.ev.pins)
        doc.ev.pins.append(StaffPin(name: role == "pro" ? "Golf pro" : "Marshal \(doc.ev.pins.filter { $0.role == "marshal" }.count + 1)", role: role, pin: pin))
    }
}

// MARK: - report

struct ReportView: View {
    @Bindable var doc: DeskDoc
    @State private var file: CSVFile?

    var body: some View {
        DeskPage(doc: doc, section: .report, save: false) {
            Button { Task { await doc.refreshDay() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }.buttonStyle(GlassButton())
            Button("Results (CSV)…") { export("results", results()) }.buttonStyle(WhiteButton())
        } title: {
            HeroTitle(title: "Report", size: 52, sub: "Results, sponsors and GHIN posting", subBeside: true)
        } content: {
            CardForm {
            SwiftUI.Section {
                HStack {
                    Button("Results (CSV)…") { export("results", results()) }.buttonStyle(.borderedProminent)
                    Button("Sponsor Report (CSV)…") { export("sponsors", sponsors()) }
                    Button("Scores for GHIN Posting (CSV)…") { if let r = ghin() { export("ghin-posting", r) } }
                    Spacer()
                    Button { Task { await doc.refreshDay() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                }
            } header: { Text("Download") } footer: {
                Help("The GHIN file has each player’s GHIN number, tees, rating and slope, hole-by-hole scores and the adjusted gross score (each hole capped at net double bogey, picked-up holes counted as net double bogey), ready for the club’s handicap chair. Scramble scores can’t be posted for handicaps.")
            }
            SwiftUI.Section {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow { Text("Sponsor"); Text("Where"); Text("Screen time"); Text("Phone views"); Text("Taps") }.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(doc.ev.sponsors) { s in
                        let st = doc.ev.stats[s.id]
                        GridRow {
                            Text(s.name).fontWeight(.medium)
                            Text((SPOT_NAMES.first { $0.0 == s.spot }?.1 ?? "") + (s.holes.isEmpty ? "" : " · " + s.holes.map(String.init).joined(separator: ", "))).foregroundStyle(.secondary)
                            Text("\(Int((st?.secs ?? 0) / 60)) min").monospacedDigit()
                            Text("\(Int(st?.view ?? 0))").monospacedDigit()
                            Text("\(Int(st?.tap ?? 0))").monospacedDigit()
                        }
                    }
                }
                if doc.ev.sponsors.isEmpty { Text("No sponsors.").foregroundStyle(.secondary) }
            } header: { Text("Sponsors") } footer: { Help("Screen time counts every minute a sponsor was on a connected screen. Phone views count each time a player saw it on their scorecard; taps count opens of their link.") }
            SwiftUI.Section("Score changes by staff") {
                if doc.ev.log.isEmpty { Text("None.").foregroundStyle(.secondary) }
                ForEach(Array(doc.ev.log.reversed().enumerated()), id: \.offset) { _, l in
                    HStack {
                        Text(Date(timeIntervalSince1970: l.at / 1000).formatted(date: .omitted, time: .shortened)).monospacedDigit().foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                        Text("\(l.by): \(l.player) (\(l.team)), hole \(l.h): \(l.from.map(String.init) ?? "–") → \(l.to.map(String.init) ?? "removed")")
                    }
                }
            }
        }
            }
        .task { await doc.refreshDay() }
        .fileExporter(isPresented: Binding(get: { file != nil }, set: { if !$0 { file = nil } }), document: file, contentType: .commaSeparatedText, defaultFilename: file?.name) { _ in file = nil }
    }

    private func export(_ what: String, _ rows: [[String]]) {
        let name = "\(doc.ev.name.isEmpty ? "Tournament" : doc.ev.name.replacingOccurrences(of: "/", with: "-")) - \(what).csv"
        file = CSVFile(name: name, rows: rows)
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
            return [s.name, SPOT_NAMES.first { $0.0 == s.spot }?.1 ?? "", s.holes.map(String.init).joined(separator: " "), "\(Int((st?.secs ?? 0) / 60))", "\(Int(st?.view ?? 0))", "\(Int(st?.tap ?? 0))"]
        }
    }
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

import UniformTypeIdentifiers
struct CSVFile: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var name: String, rows: [[String]]
    init(name: String, rows: [[String]]) { self.name = name; self.rows = rows }
    init(configuration: ReadConfiguration) throws { name = ""; rows = [] }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let text = rows.map { $0.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ",") }.joined(separator: "\r\n")
        return FileWrapper(regularFileWithContents: Data(("\u{FEFF}" + text).utf8))
    }
}
