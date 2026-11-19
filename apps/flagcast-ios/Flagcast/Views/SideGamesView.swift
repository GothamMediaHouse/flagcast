import SwiftUI

/// The cart's own skins, Nassau and birdies (ported from the web scorecard). The scores the cart enters play
/// every game; Flagcast only does the math and never takes or holds money. Settings stay on this phone.
struct SideGamesSheet: View {
    @Bindable var model: ScorecardModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let r = model.sideResult() { content(r) } else { ProgressView() }
            }
            .navigationTitle("Side games")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func content(_ r: SideResult) -> some View {
        let P = Dictionary(uniqueKeysWithValues: r.players.map { ($0.key, $0) })
        func nm(_ k: String) -> String { P[k]?.short ?? "" }
        return Form {
            Section {
                Text("Games among the \(r.players.count) players in your cart. The scores you enter play every game, and the money adds up at the bottom.")
                    .font(.subheadline).foregroundStyle(Color.fcMuted)
                if r.players.count < 2 { Text("Side games need at least two players in your cart.").font(.subheadline.weight(.semibold)) }
            }

            Section {
                Toggle("Play skins", isOn: $model.side.skins.on)
                amount("A skin, from each player", $model.side.skins.amt)
                netPicker($model.side.skins.net)
                Toggle("Ties carry over", isOn: Binding(get: { model.side.skins.carry != false }, set: { model.side.skins.carry = $0 }))
                if let sk = r.skins {
                    FlowLayout(spacing: 5) {
                        ForEach(sk.rows, id: \.hole) { row in
                            switch row {
                            case let .won(h, w, _, worth): holeChip("\(h) \(nm(w))\(worth > 1 ? " ×\(worth)" : "")", won: true)
                            case let .tied(h, _, _, _): holeChip("\(h) tie", won: false, strong: true)
                            case let .open(h, _): holeChip("\(h)", won: false)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    ForEach(r.players, id: \.key) { p in LabeledContent(p.short) { Text("\(sk.won[p.key] ?? 0)").monospacedDigit() } }
                    if sk.carrying > 0 { Text("\(sk.carrying) skin\(sk.carrying > 1 ? "s" : "") carrying to the next hole.").font(.footnote).foregroundStyle(Color.fcMuted) }
                }
            } header: { Text("Skins") }

            Section {
                Toggle("Play Nassau", isOn: $model.side.nassau.on)
                amount("Each on the front 9, back 9 and overall", $model.side.nassau.amt)
                netPicker($model.side.nassau.net)
                if let na = r.nassau {
                    let inA = Set(na.sides["A"] ?? [])
                    ForEach(r.players, id: \.key) { p in
                        Picker(p.short, selection: Binding(get: { inA.contains(p.key) ? "A" : "B" }, set: { model.side.nassau.sides[p.key] = $0 })) {
                            Text("Side A").tag("A"); Text("Side B").tag("B")
                        }
                    }
                    let sideName = { (s: String) in (na.sides[s] ?? []).map(nm).joined(separator: " & ") }
                    ForEach(na.segs, id: \.label) { g in
                        let st = g.played == 0 ? "Not started"
                            : g.done ? (g.winner.map { "\(sideName($0)) win, \(abs(g.diff)) up" } ?? "Tied, no money")
                            : g.diff != 0 ? "\(sideName(g.diff > 0 ? "A" : "B")) \(abs(g.diff)) up thru \(g.played)" : "All square thru \(g.played)"
                        LabeledContent(g.label) { Text(st).font(.subheadline.weight(.semibold)).multilineTextAlignment(.trailing) }
                    }
                } else if model.side.nassau.on && r.players.count >= 2 {
                    Text("Put at least one player on each side.").font(.footnote).foregroundStyle(Color.fcMuted)
                }
            } header: { Text("Nassau") }

            Section {
                Toggle("Play birdies", isOn: $model.side.birdies.on)
                amount("A birdie, from each player (an eagle counts twice)", $model.side.birdies.amt)
                netPicker($model.side.birdies.net)
                if let b = r.birdies {
                    if b.isEmpty { Text("No birdies yet.").font(.footnote).foregroundStyle(Color.fcMuted) }
                    else {
                        FlowLayout(spacing: 5) { ForEach(Array(b.enumerated()), id: \.offset) { _, x in holeChip("\(x.hole) \(nm(x.key))\(x.eagle ? " eagle" : "")", won: true) } }
                            .padding(.vertical, 4)
                    }
                }
            } header: { Text("Birdies") }

            if r.skins != nil || r.nassau != nil || r.birdies != nil {
                Section {
                    if r.settle.isEmpty { Text("Nobody owes anything yet.").foregroundStyle(Color.fcMuted) }
                    ForEach(Array(r.settle.enumerated()), id: \.offset) { _, x in
                        LabeledContent("\(nm(x.from)) pays \(nm(x.to))") { Text(Fmt.money(x.amt)).font(.body.monospaced().weight(.semibold)) }
                    }
                    ForEach(r.players, id: \.key) { p in
                        let v = jsRound((r.ledger[p.key] ?? 0) * 100) / 100
                        LabeledContent(p.short) {
                            Text(v == 0 ? "Even" : "\(v > 0 ? "+" : "−")\(Fmt.money(v))").monospacedDigit().foregroundStyle(v < 0 ? Color.fcRed : Color.fcInk)
                        }
                    }
                } header: { Text("Who owes who") } footer: {
                    Text("Running totals so far. Settle up among yourselves after the round. Flagcast never takes or holds money. These game settings are kept on this phone.")
                }
            }
        }
        .tint(Color.fcGreen2)
    }

    private func amount(_ label: String, _ v: Binding<Double>) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            HStack(spacing: 2) {
                Text("$").foregroundStyle(Color.fcMuted)
                TextField("0", value: v, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    .onChange(of: v.wrappedValue) { _, x in if x < 0 || x > 10000 { v.wrappedValue = min(10000, max(0, x)) } }
            }
            .font(.body.monospaced().weight(.semibold))
            .frame(width: 84)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(Color.fcPaper, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Dollars: \(label)")
        }
    }
    private func netPicker(_ v: Binding<Bool>) -> some View {
        Picker("Scoring", selection: v) { Text("Net (with strokes)").tag(true); Text("Gross").tag(false) }
    }
    private func holeChip(_ t: String, won: Bool, strong: Bool = false) -> some View {
        Text(t).font(.caption.monospaced()).padding(.horizontal, 7).padding(.vertical, 4)
            .background(won ? Color.fcGreen2 : Color.fcPaper2, in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(won ? Color.fcOnGreen : strong ? Color.fcInk : Color.fcMuted)
    }
}
