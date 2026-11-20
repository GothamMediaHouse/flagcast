import SwiftUI

/// Scores: every team's card, hole by hole. Fix any score; it saves at once and shows on every screen.
/// 0 = picked up, empty = no score. Live: scores from the carts appear as they come in.
struct ScoresView: View {
    @Bindable var doc: DeskDoc
    @State private var search = ""
    @State private var editing: Cell?
    @State private var text = ""
    @FocusState private var focused: Bool
    struct Cell: Hashable { var team: String, p: String, h: Int }

    private var holes: [Hole] { doc.ev.course.holes.filter { doc.ev.playHoles.contains($0.n) } }
    private var teams: [DeskTeam] {
        let q = search.lowercased()
        return doc.ev.teams.filter { q.isEmpty || $0.displayName.lowercased().contains(q) || $0.players.contains { $0.name.lowercased().contains(q) } }
            .sorted { ($0.start, $0.displayName) < ($1.start, $1.displayName) }
    }
    private func who(_ t: DeskTeam) -> [(id: String, name: String)] {
        doc.ev.format.isScramble ? [("T", t.displayName.isEmpty ? "Team" : t.displayName)] : t.players.map { ($0.id, $0.name) }
    }
    private func value(_ c: Cell) -> Int? {
        guard let arr = doc.live?.scores[c.team]?[c.p], c.h - 1 < arr.count else { return nil }
        return arr[c.h - 1]
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .center, horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    Text("Team").gridColumnAlignment(.leading).frame(width: 200, alignment: .leading)
                    Text("Player").gridColumnAlignment(.leading).frame(width: 150, alignment: .leading)
                    ForEach(holes, id: \.n) { h in VStack(spacing: 0) { Text("\(h.n)"); Text("par \(h.par)").font(.caption2).foregroundStyle(.tertiary) }.frame(width: 38) }
                    Text("Total").frame(width: 50)
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(teams) { t in
                    ForEach(Array(who(t).enumerated()), id: \.offset) { k, p in
                        GridRow {
                            Text(k == 0 ? t.displayName : "").fontWeight(.medium).lineLimit(1).frame(width: 200, alignment: .leading)
                            Text(p.name).lineLimit(1).frame(width: 150, alignment: .leading).foregroundStyle(.secondary)
                            ForEach(holes, id: \.n) { h in cell(Cell(team: t.id, p: p.id, h: h.n), par: h.par) }
                            Text(total(t.id, p.id)).monospacedDigit().fontWeight(.semibold).frame(width: 50)
                        }
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                }
            }
            .padding(16)
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Find a team or player")
        .overlay {
            if doc.ev.teams.isEmpty { ContentUnavailableView("No teams yet", systemImage: "tablecells", description: Text("Add teams on the Teams page, then Save.")) }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Circle().fill(doc.feed.online ? Color.green : Color.orange).frame(width: 7, height: 7)
                Text(doc.feed.online ? "Live: scores from the carts appear as they come in." : "Reconnecting…")
                Spacer()
                Text("Click a score to fix it. Type 0 for a picked-up ball; clear it to remove the score.")
            }
            .font(.callout).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 8).background(.bar)
        }
    }

    @ViewBuilder private func cell(_ c: Cell, par: Int) -> some View {
        if editing == c {
            TextField("", text: $text).focused($focused).multilineTextAlignment(.center).frame(width: 38, height: 26)
                .onSubmit { commit(c) }.onExitCommand { editing = nil }
                .onChange(of: focused) { _, f in if !f && editing == c { commit(c) } }
        } else {
            let v = value(c)
            Button { text = v.map(String.init) ?? ""; editing = c; focused = true } label: {
                Text(v.map { $0 == 0 ? "PU" : "\($0)" } ?? "·").monospacedDigit()
                    .frame(width: 38, height: 26)
                    .background(mark(v, par).opacity(v == nil ? 0 : 1), in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(v == nil ? Color.secondary.opacity(0.5) : .primary)
            }
            .buttonStyle(.plain)
        }
    }
    private func mark(_ v: Int?, _ par: Int) -> Color {
        guard let v, v > 0 else { return Color.secondary.opacity(0.12) }
        return v < par - 1 ? .yellow.opacity(0.55) : v < par ? .red.opacity(0.28) : v == par ? .clear : v == par + 1 ? .blue.opacity(0.18) : .blue.opacity(0.32)
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
