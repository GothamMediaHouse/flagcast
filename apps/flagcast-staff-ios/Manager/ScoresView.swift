import SwiftUI

/// Scores: each team as a card, marked like a scorecard (eagle: filled red circle, birdie: red ring, bogey: blue
/// square, double: filled blue square). Tap a team to see its players and fix any score: it saves at once.
struct ScoresView: View {
    var body: some View {
        WithTournament { doc in ScoresPage(doc: doc) }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { TournamentMenu() } }
    }
}

private struct ScoresPage: View {
    @Bindable var doc: DeskDoc
    @State private var mode = ""
    @State private var flight = ""
    @State private var open: String?

    private var holes: [Hole] { doc.ev.course.holes.filter { doc.ev.playHoles.contains($0.n) } }
    private var showMode: String { mode.isEmpty ? doc.ev.format.show : mode }
    private var lines: [Line] {
        guard let live = doc.live else { return [] }
        return Core.leaderboard(live, live.scores, flight: flight.isEmpty ? nil : flight, mode: showMode)
    }
    private var scoring: Int { lines.filter { $0.played > 0 && $0.thru != "F" }.count }

    var body: some View {
        PhotoPage(image: doc.picture.image, kicker: doc.feed.online ? "From the carts · \(scoring) of \(doc.ev.teams.count) scoring" : "Reconnecting…",
                  live: doc.feed.online && scoring > 0, title: "Live scores", height: 220) {
            if !doc.ev.format.isStableford {
                Picker("", selection: Binding(get: { showMode }, set: { mode = $0 })) { Text("Net").tag("net"); Text("Gross").tag("gross") }
                    .pickerStyle(.segmented).frame(width: 170).colorScheme(.light)
            }
        } content: {
            if doc.ev.flights.count > 1 {
                Picker("Flight", selection: $flight) { Text("All").tag(""); ForEach(doc.ev.flights, id: \.self) { Text("Flight \($0)").tag($0) } }.pickerStyle(.segmented)
            }
            if lines.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.number").font(.system(size: 30)).foregroundStyle(FC.muted)
                    Text(doc.ev.teams.isEmpty ? "No teams yet" : "No scores yet").font(.headline)
                    Text(doc.ev.teams.isEmpty ? "Add teams on the Teams tab, then Save." : "Scores appear here as the carts send them.").font(.subheadline).foregroundStyle(FC.muted)
                }
                .frame(maxWidth: .infinity).card(padding: 24)
            }
            ForEach(lines) { l in
                Button { open = l.teamId } label: { ScoreCard(line: l, holes: holes, mode: showMode, stab: doc.ev.format.isStableford) }.buttonStyle(.plain)
            }
            legend
        }
        .refreshable { await doc.feed.refresh() }
        .sheet(item: Binding(get: { open.map { EditID(id: $0) } }, set: { open = $0?.id })) { e in
            NavigationStack { FixScores(doc: doc, teamId: e.id, holes: holes) }.presentationDetents([.medium, .large])
        }
    }
    private var legend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) { Circle().fill(FC.red).frame(width: 12, height: 12); Text("Eagle") }
            HStack(spacing: 4) { Circle().stroke(FC.red, lineWidth: 2).frame(width: 11, height: 11); Text("Birdie") }
            HStack(spacing: 4) { Rectangle().stroke(FC.blue, lineWidth: 2).frame(width: 11, height: 11); Text("Bogey") }
            HStack(spacing: 4) { Rectangle().fill(FC.blue).frame(width: 12, height: 12); Text("Double+") }
        }
        .font(.caption).foregroundStyle(FC.muted).frame(maxWidth: .infinity)
    }
}

/// One team's line: position, name, thru, score, and its card marked hole by hole.
private struct ScoreCard: View {
    let line: Line
    let holes: [Hole]
    let mode: String
    let stab: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(line.pos).font(.system(size: 15, weight: .bold)).foregroundStyle(FC.muted).frame(width: 30, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(line.name).font(.headline).foregroundStyle(FC.ink).lineLimit(1)
                    Text(line.played == 0 ? "Not started" : line.thru == "F" ? "Finished" : "Thru \(line.thru)").font(.caption).foregroundStyle(FC.muted)
                }
                Spacer()
                Text(line.played == 0 ? "–" : stab ? "\(line.score)" : Core.fmtPar(line.score)).font(FC.display(32))
                    .foregroundStyle(stab || line.played == 0 ? FC.ink : line.score < 0 ? FC.red : line.score > 0 ? FC.blue : FC.ink)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(holes, id: \.n) { h in
                        let r = line.card.first { $0.hole == h.n }
                        VStack(spacing: 2) {
                            Text("\(h.n)").font(.system(size: 9, weight: .semibold)).foregroundStyle(FC.muted)
                            ScoreMark(v: r.flatMap { $0.done ? (mode == "gross" ? $0.gross : $0.net) : nil }, par: r?.par ?? h.par, size: 26)
                        }
                    }
                }
            }
        }
        .card(padding: 14)
    }
}

/// A score marked like a scorecard. 0 (raw) = picked up.
struct ScoreMark: View {
    var v: Int?
    var par: Int
    var size: CGFloat = 30
    var raw = false
    var body: some View {
        let d = (v ?? par) - par
        ZStack {
            if let v, !(raw && v == 0) {
                if d <= -2 { Circle().fill(FC.red) }
                else if d == -1 { Circle().stroke(FC.red, lineWidth: 2) }
                else if d == 1 { Rectangle().stroke(FC.blue, lineWidth: 2) }
                else if d >= 2 { Rectangle().fill(FC.blue) }
            }
            Text(v.map { raw && $0 == 0 ? "PU" : "\($0)" } ?? "·")
                .font(.system(size: raw && v == 0 ? 10 : size * 0.5, weight: .bold).monospacedDigit())
                .foregroundStyle(v == nil ? FC.muted.opacity(0.5) : d <= -2 || d >= 2 ? .white : d == -1 ? FC.red : d == 1 ? FC.blue : FC.ink)
        }
        .frame(width: size, height: size)
    }
}

/// A team's players hole by hole: tap a score to fix it (saved at once, on every screen and phone).
private struct FixScores: View {
    let doc: DeskDoc
    let teamId: String
    let holes: [Hole]
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Cell?
    struct Cell: Identifiable, Hashable { var p: String, name: String, h: Int, par: Int; var id: String { "\(p)-\(h)" } }

    private var team: DeskTeam? { doc.ev.teams.first { $0.id == teamId } }
    private var who: [(String, String)] {
        guard let t = team else { return [] }
        return doc.ev.format.isScramble ? [("T", t.displayName.isEmpty ? "Team" : t.displayName)] : t.players.map { ($0.id, $0.name.isEmpty ? "Player" : $0.name) }
    }
    private func value(_ p: String, _ h: Int) -> Int? {
        guard let arr = doc.live?.scores[teamId]?[p], h - 1 < arr.count else { return nil }
        return arr[h - 1]
    }

    var body: some View {
        List {
            ForEach(who, id: \.0) { p in
                SwiftUI.Section(p.1) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 9), spacing: 8) {
                        ForEach(holes, id: \.n) { h in
                            Button { editing = Cell(p: p.0, name: p.1, h: h.n, par: h.par) } label: {
                                VStack(spacing: 1) {
                                    Text("\(h.n)").font(.system(size: 9, weight: .semibold)).foregroundStyle(FC.muted)
                                    ScoreMark(v: value(p.0, h.n), par: h.par, size: 30, raw: true)
                                }
                                .frame(maxWidth: .infinity).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            SwiftUI.Section { Help("Tap a score to fix it. It changes on the board and every phone right away.") }
        }
        .navigationTitle(team?.displayName ?? "Team").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(item: $editing) { c in ScorePad(cell: c, current: value(c.p, c.h)) { v in commit(c, v) }.presentationDetents([.height(360)]) }
    }
    private func commit(_ c: Cell, _ v: Int?) {
        Task {
            do {
                try await API.post(doc.id, "score", ["desk": doc.key, "team": teamId, "list": [["p": c.p, "h": c.h, "v": v.map { $0 as Any } ?? NSNull(), "at": Date().timeIntervalSince1970 * 1000]]])
                await doc.feed.refresh()
                doc.flash("Hole \(c.h) fixed for \(c.name).")
            } catch { doc.flash(error.localizedDescription) }
        }
    }
}

/// Big number buttons for one score: 1–10, picked up, or no score.
private struct ScorePad: View {
    let cell: FixScoresCell
    let current: Int?
    let set: (Int?) -> Void
    @Environment(\.dismiss) private var dismiss
    init(cell: FixScoresCellConvertible, current: Int?, set: @escaping (Int?) -> Void) { self.cell = cell.asCell; self.current = current; self.set = set }
    var body: some View {
        VStack(spacing: 14) {
            Text("\(cell.name) · Hole \(cell.h) · Par \(cell.par)").font(.headline).padding(.top, 18)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(1...10, id: \.self) { n in
                    Button { set(n); dismiss() } label: {
                        Text("\(n)").font(FC.display(28)).frame(maxWidth: .infinity, minHeight: 54)
                            .foregroundStyle(current == n ? FC.onGreen : FC.ink)
                            .background(current == n ? FC.green : FC.paper2, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                Button("Picked up") { set(0); dismiss() }.buttonStyle(PlainCardButton(full: true))
                Button("No score") { set(nil); dismiss() }.buttonStyle(PlainCardButton(full: true))
            }
        }
        .padding(.horizontal, 16)
    }
}
struct FixScoresCell { var p: String, name: String, h: Int, par: Int }
protocol FixScoresCellConvertible { var asCell: FixScoresCell { get } }
extension FixScores.Cell: FixScoresCellConvertible { var asCell: FixScoresCell { FixScoresCell(p: p, name: name, h: h, par: par) } }
