import SwiftUI

/// Scores (design/Scores.dc.html): "Live scores · FROM THE CARTS" over the photo; a table card with the green hole
/// header, the par row and each team's card marked like a scorecard (eagle: filled red circle, birdie: red ring,
/// bogey: blue square, double: filled blue square). Click a team to see its players and fix any score: it saves at
/// once and shows on every screen.
struct ScoresView: View {
    @Bindable var doc: DeskDoc
    @Environment(DeskNav.self) private var nav
    @State private var mode = ""
    @State private var open: String?
    @State private var editing: Cell?
    @State private var text = ""
    @FocusState private var focused: Bool
    struct Cell: Hashable { var team: String, p: String, h: Int }

    private var holes: [Hole] { doc.ev.course.holes.filter { doc.ev.playHoles.contains($0.n) } }
    private var showMode: String { mode.isEmpty ? doc.ev.format.show : mode }
    private var lines: [Line] {
        guard let live = doc.live else { return [] }
        let q = nav.search.lowercased()
        return Core.leaderboard(live, live.scores, mode: showMode).filter { q.isEmpty || $0.name.lowercased().contains(q) || $0.sub.lowercased().contains(q) }
    }
    private var cell: CGFloat { holes.count > 9 ? 34 : 52 }
    private var scoring: Int { lines.filter { $0.played > 0 && $0.thru != "F" }.count }

    var body: some View {
        DeskPage(doc: doc, section: .scores, height: 250, titleHeight: 142, save: false) {
            PhotoSegments(options: [("Net", "net"), ("Gross", "gross")], selection: Binding(get: { showMode }, set: { mode = $0 }))
            Button("Export") { nav.section = .report }.buttonStyle(GlassButton())
            LockButton(doc: doc, white: true)
        } title: {
            HStack(alignment: .lastTextBaseline, spacing: 16) {
                Text("Live scores").font(FC.display(56))
                HStack(spacing: 6) {
                    Circle().fill(doc.feed.online ? Color(hex: 0xff6b60) : .gray).frame(width: 8, height: 8)
                    Text(doc.feed.online ? "FROM THE CARTS · \(scoring) OF \(doc.ev.teams.count) SCORING" : "RECONNECTING…").font(.system(size: 12, weight: .bold)).tracking(1)
                }
                .padding(.bottom, 8)
            }
            .shadow(color: .black.opacity(0.35), radius: 8, y: 1).padding(.bottom, 18)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        header
                        parRow
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                ForEach(lines) { l in teamRow(l); if open == l.teamId { playerRows(l) } }
                                if lines.isEmpty { empty }
                            }
                        }
                    }
                    .frame(minWidth: 44 + 170 + CGFloat(holes.count) * cell + 128 + 28)
                }
                .background(FC.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(FC.line))
                .shadow(color: FC.scrim.opacity(0.18), radius: 15, y: 8)
                legend
            }
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 18)
        }
    }

    // ---- rows ----
    private var header: some View {
        HStack(spacing: 0) {
            Text("POS").frame(width: 44, alignment: .leading)
            Text("TEAM").frame(minWidth: 170, maxWidth: .infinity, alignment: .leading)
            ForEach(holes, id: \.n) { h in Text("\(h.n)").frame(width: cell) }
            Text("THRU").frame(width: 64); Text("TOTAL").frame(width: 64)
        }
        .font(.system(size: 12, weight: .bold)).foregroundStyle(FC.onGreen)
        .padding(.horizontal, 14).frame(height: 40).background(FC.green)
    }
    private var parRow: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 44)
            Text("Par").frame(minWidth: 170, maxWidth: .infinity, alignment: .leading)
            ForEach(holes, id: \.n) { h in Text("\(h.par)").frame(width: cell) }
            Color.clear.frame(width: 64); Text("\(holes.reduce(0) { $0 + $1.par })").frame(width: 64)
        }
        .font(.system(size: 12, weight: .semibold)).foregroundStyle(FC.muted)
        .padding(.horizontal, 14).frame(height: 30).background(FC.paper2)
    }
    private func teamRow(_ l: Line) -> some View {
        let isOpen = open == l.teamId
        return HStack(spacing: 0) {
            Text(l.pos).font(.system(size: 14, weight: .bold)).foregroundStyle(FC.muted).frame(width: 44, alignment: .leading)
            HStack(spacing: 6) {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(FC.muted)
                Text(l.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            }
            .frame(minWidth: 170, maxWidth: .infinity, alignment: .leading)
            ForEach(holes, id: \.n) { h in
                let r = l.card.first { $0.hole == h.n }
                let v = r.flatMap { $0.done ? (showMode == "gross" ? $0.gross : $0.net) : nil }
                ScoreMark(v: v, par: r?.par ?? h.par, size: holes.count > 9 ? 25 : 30).frame(width: cell)
            }
            Text(l.played == 0 ? "–" : l.thru).font(.system(size: 13)).foregroundStyle(FC.muted).frame(width: 64)
            Text(l.played == 0 ? "–" : doc.ev.format.isStableford ? "\(l.score)" : Core.fmtPar(l.score)).font(FC.display(24))
                .foregroundStyle(doc.ev.format.isStableford || l.played == 0 ? FC.ink : l.score < 0 ? FC.red : l.score > 0 ? FC.blue : FC.ink).frame(width: 64)
        }
        .padding(.horizontal, 14).frame(height: 44)
        .background(isOpen ? FC.paper2.opacity(0.5) : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(FC.hairline).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { open = isOpen ? nil : l.teamId } }
        .help("Click to see the players and fix a score")
    }
    @ViewBuilder private func playerRows(_ l: Line) -> some View {
        if let t = doc.ev.teams.first(where: { $0.id == l.teamId }) {
            let who: [(String, String)] = doc.ev.format.isScramble ? [("T", t.displayName.isEmpty ? "Team" : t.displayName)] : t.players.map { ($0.id, $0.name) }
            ForEach(who, id: \.0) { p in
                HStack(spacing: 0) {
                    Color.clear.frame(width: 44)
                    Text(p.1).font(.system(size: 13)).foregroundStyle(FC.muted).padding(.leading, 15).frame(minWidth: 170, maxWidth: .infinity, alignment: .leading)
                    ForEach(holes, id: \.n) { h in editCell(Cell(team: t.id, p: p.0, h: h.n), par: h.par).frame(width: cell) }
                    Color.clear.frame(width: 64)
                    Text(total(t.id, p.0)).font(.system(size: 13, weight: .semibold).monospacedDigit()).frame(width: 64)
                }
                .padding(.horizontal, 14).frame(height: 38).background(FC.paper2.opacity(0.35))
                .overlay(alignment: .bottom) { Rectangle().fill(FC.hairline).frame(height: 1) }
            }
        }
    }
    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.number").font(.system(size: 30)).foregroundStyle(FC.muted)
            Text(doc.ev.teams.isEmpty ? "No teams yet" : "No scores yet").font(.headline)
            Text(doc.ev.teams.isEmpty ? "Add teams on the Teams page, then Save." : "Scores appear here as the carts send them.").font(.callout).foregroundStyle(FC.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
    private var legend: some View {
        HStack(spacing: 18) {
            HStack(spacing: 6) { Circle().fill(FC.red).frame(width: 18, height: 18); Text("Eagle or better") }
            HStack(spacing: 6) { Circle().stroke(FC.red, lineWidth: 2).frame(width: 16, height: 16); Text("Birdie") }
            HStack(spacing: 6) { Rectangle().stroke(FC.blue, lineWidth: 2).frame(width: 16, height: 16); Text("Bogey") }
            HStack(spacing: 6) { Rectangle().fill(FC.blue).frame(width: 18, height: 18); Text("Double or worse") }
            Spacer()
            Text("Click a team to fix a score. Changes go to the board and phones right away.")
        }
        .font(.system(size: 12)).foregroundStyle(FC.muted)
    }

    // ---- fixing a score ----
    private func value(_ c: Cell) -> Int? {
        guard let arr = doc.live?.scores[c.team]?[c.p], c.h - 1 < arr.count else { return nil }
        return arr[c.h - 1]
    }
    @ViewBuilder private func editCell(_ c: Cell, par: Int) -> some View {
        if editing == c {
            TextField("", text: $text).textFieldStyle(.roundedBorder).focused($focused).multilineTextAlignment(.center).frame(width: 34)
                .onSubmit { commit(c) }.onExitCommand { editing = nil }
                .onChange(of: focused) { _, f in if !f && editing == c { commit(c) } }
        } else {
            let v = value(c)
            Button { text = v.map(String.init) ?? ""; editing = c; focused = true } label: {
                ScoreMark(v: v, par: par, size: 24, raw: true).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Click to fix (0 = picked up, empty = no score)")
        }
    }
    private func total(_ team: String, _ p: String) -> String {
        let arr = doc.live?.scores[team]?[p] ?? []
        let t = holes.reduce(0) { s, h in s + (h.n - 1 < arr.count ? max(0, arr[h.n - 1] ?? 0) : 0) }
        return t > 0 ? "\(t)" : ""
    }
    private func commit(_ c: Cell) {
        let t = text.trimmingCharacters(in: .whitespaces)
        editing = nil
        let v: Int? = t.isEmpty ? nil : Int(t)
        if !t.isEmpty, (v == nil || !(0...15).contains(v!)) { doc.flash("Use a number from 0 (picked up) to 15."); return }
        if v == value(c) { return }
        Task {
            do {
                try await API.post(doc.id, "score", ["desk": doc.key, "team": c.team, "list": [["p": c.p, "h": c.h, "v": v.map { $0 as Any } ?? NSNull(), "at": Date().timeIntervalSince1970 * 1000]]])
                await doc.feed.refresh()
            } catch { doc.flash(error.localizedDescription) }
        }
    }
}

/// A score marked like a scorecard: eagle or better a filled red circle, birdie a red ring, par plain,
/// bogey a blue square outline, double or worse a filled blue square. 0 (raw) = picked up.
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
