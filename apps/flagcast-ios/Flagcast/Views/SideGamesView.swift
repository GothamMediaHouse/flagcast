import SwiftUI

/// The cart's own side games: the same games and math as the web scorecard (core.js sideGames, checked by CoreTests).
/// The scores the cart enters play every game. Games are for points only: Flagcast has no money in it.
/// Settings stay on this phone.
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
        let n = r.players.count
        return Form {
            Section {
                if n >= 2 {
                    Text("Games among the \(n) players in your cart. The scores you enter play every game, and the points add up at the bottom.")
                        .font(.subheadline).foregroundStyle(Color.fcMuted)
                } else {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(n == 1 ? "You're the only player in your cart." : "Nobody is in your cart yet.").font(.subheadline.weight(.semibold))
                            Text("Side games need at least two players. They open up here once your cart has two or more.")
                                .font(.subheadline).foregroundStyle(Color.fcMuted)
                        }
                    } icon: { Image(systemName: "person.2").foregroundStyle(Color.fcMuted) }
                }
            }

            if n >= 2 { games(r, nm) }
        }
        .tint(Color.fcPrimary)  // toggles: a green that shows on dark (the Done button keeps the app's own colour)
    }

    @ViewBuilder
    private func games(_ r: SideResult, _ nm: @escaping (String) -> String) -> some View {
        let n = r.players.count
        // ---- skins ----
        Section {
            Toggle("Play skins", isOn: $model.side.skins.on)
            if model.side.skins.on {
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
                    ForEach(r.players, id: \.key) { p in LabeledContent(p.short) { Text("\(sk.won[p.key] ?? 0) won").monospacedDigit() } }
                    if sk.carrying > 0 { Text("\(sk.carrying) skin\(sk.carrying > 1 ? "s" : "") carrying to the next hole.").font(.footnote).foregroundStyle(Color.fcMuted) }
                }
            }
        } header: { Text("Skins") } footer: { if !model.side.skins.on { Text("Lowest score alone wins the hole.") } }

        // ---- Nassau ----
        Section {
            Toggle("Play Nassau", isOn: $model.side.nassau.on)
            if model.side.nassau.on {
                amount("Each on the front 9, back 9 and overall", $model.side.nassau.amt)
                netPicker($model.side.nassau.net)
                if let na = r.nassau {
                    let inA = Set(na.sides["A"] ?? [])
                    ForEach(r.players, id: \.key) { p in
                        sidePicker(p.short, Binding(get: { inA.contains(p.key) ? "A" : "B" }, set: { model.side.nassau.sides[p.key] = $0 }))
                    }
                    let sideName = { (s: String) in (na.sides[s] ?? []).map(nm).joined(separator: " & ") }
                    ForEach(na.segs, id: \.label) { g in
                        let st = g.played == 0 ? "Not started"
                            : g.done ? (g.winner.map { "\(sideName($0)) win, \(abs(g.diff)) up" } ?? "Tied, no points")
                            : g.diff != 0 ? "\(sideName(g.diff > 0 ? "A" : "B")) \(abs(g.diff)) up thru \(g.played)" : "All square thru \(g.played)"
                        LabeledContent(g.label) { Text(st).font(.subheadline.weight(.semibold)).foregroundStyle(Color.fcInk).multilineTextAlignment(.trailing) }
                    }
                } else {
                    Text("Put at least one player on each side.").font(.footnote).foregroundStyle(Color.fcMuted)
                }
            }
        } header: { Text("Nassau") } footer: { if !model.side.nassau.on { Text("Two sides, three matches: the front 9, the back 9 and the whole round.") } }

        // ---- birdies ----
        Section {
            Toggle("Play birdies", isOn: $model.side.birdies.on)
            if model.side.birdies.on {
                amount("A birdie, from each player (an eagle counts twice)", $model.side.birdies.amt)
                netPicker($model.side.birdies.net)
                if let b = r.birdies {
                    if b.isEmpty { Text("No birdies yet.").font(.footnote).foregroundStyle(Color.fcMuted) }
                    else {
                        FlowLayout(spacing: 5) { ForEach(Array(b.enumerated()), id: \.offset) { _, x in holeChip("\(x.hole) \(nm(x.key))\(x.eagle ? " eagle" : "")", won: true) } }
                            .padding(.vertical, 4)
                    }
                }
            }
        } header: { Text("Birdies") }

        // ---- Stableford ----
        Section {
            Toggle("Play Stableford", isOn: $model.side.stableford.on)
            if model.side.stableford.on {
                netPicker($model.side.stableford.net)
                if let sf = r.stableford {
                    ForEach(sf.sorted { $0.points > $1.points }, id: \.key) { row in
                        LabeledContent(nm(row.key)) {
                            Text(row.thru == 0 ? "–" : "\(row.points) pts thru \(row.thru)").monospacedDigit().foregroundStyle(Color.fcInk)
                        }
                    }
                }
            }
        } header: { Text("Stableford") } footer: {
            Text("Points against par on every hole: double bogey or worse 0, bogey 1, par 2, birdie 3, eagle 4. Most points wins. Its points stay in this table.")
        }

        // ---- Vegas ----
        Section {
            Toggle("Play Vegas", isOn: $model.side.vegas.on)
            if model.side.vegas.on {
                amount("Each point of difference", $model.side.vegas.amt)
                netPicker($model.side.vegas.net)
                if n == 4, let vg = r.vegas {
                    let inA = Set(vg.sides["A"] ?? [])
                    ForEach(r.players, id: \.key) { p in
                        sidePicker(p.short, Binding(get: { inA.contains(p.key) ? "A" : "B" }, set: { model.side.vegas.sides[p.key] = $0 }))
                    }
                }
                if let vg = r.vegas, !r.vegasNeedsFour {
                    let sideName = { (s: String) in (vg.sides[s] ?? []).map(nm).joined(separator: " & ") }
                    if vg.holes.isEmpty { Text("No holes finished yet.").font(.footnote).foregroundStyle(Color.fcMuted) }
                    else {
                        FlowLayout(spacing: 5) {
                            ForEach(vg.holes, id: \.hole) { h in holeChip("\(h.hole) \(h.a)–\(h.b)", won: h.a != h.b) }
                        }.padding(.vertical, 4)
                        LabeledContent("Running") {
                            Text(vg.total == 0 ? "All square" : "\(sideName(vg.total > 0 ? "A" : "B")) +\(abs(vg.total))")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.fcInk)
                        }
                    }
                } else {
                    Text(n == 4 ? "Put two players on each side." : "Vegas needs exactly four players, two on each side.")
                        .font(.footnote).foregroundStyle(Color.fcMuted)
                }
            }
        } header: { Text("Vegas") } footer: {
            if !model.side.vegas.on { Text("Two against two. Each side's scores make a number, low score first (a 4 and a 5 make 45). The lower number wins the difference.") }
        }

        // ---- Wolf ----
        Section {
            Toggle("Play Wolf", isOn: $model.side.wolf.on)
            if model.side.wolf.on {
                amount("Each hole (a lone wolf plays for double)", $model.side.wolf.amt)
                netPicker($model.side.wolf.net)
                if let wf = r.wolf {
                    NavigationLink {
                        WolfPicks(model: model)
                    } label: {
                        LabeledContent("Wolf picks") {
                            Text("\(wf.holes.filter { $0.partner != nil }.count) of \(wf.holes.count) holes").foregroundStyle(Color.fcInk)
                        }
                    }
                    if let next = wf.holes.first(where: { $0.partner == nil }) {
                        LabeledContent("Next up") { Text("Hole \(next.hole): \(nm(next.wolf)) is the wolf").foregroundStyle(Color.fcInk) }
                    }
                } else {
                    Text("Wolf needs three or four players.").font(.footnote).foregroundStyle(Color.fcMuted)
                }
            }
        } header: { Text("Wolf") } footer: {
            if !model.side.wolf.on { Text("The wolf rotates each hole. After the tee shots the wolf takes a partner or goes it alone, then the best ball on each side wins the hole.") }
        }

        // ---- closest to the pin and long drive ----
        pickSection("Closest to the pin", "Play closest to the pin", $model.side.closest, r.closest, r, nm,
                    empty: "This course has no par 3s.", about: "On each par 3, pick who's closest. Everyone else gives them the points.")
        pickSection("Long drive", "Play long drive", $model.side.longDrive, r.longDrive, r, nm,
                    empty: "This course has no par 5s.", about: "On each par 5, pick who hit the longest drive in the fairway.")

        // ---- totals ----
        if hasPointGames(r) {
            Section {
                ForEach(r.players.sorted { (r.ledger[$0.key] ?? 0) > (r.ledger[$1.key] ?? 0) }, id: \.key) { p in
                    let v = jsRound((r.ledger[p.key] ?? 0) * 100) / 100
                    LabeledContent(p.short) {
                        Text(v == 0 ? "Even" : "\(v > 0 ? "+" : "−")\(fmtPts(abs(v)))").monospacedDigit().font(.body.weight(.semibold))
                            .foregroundStyle(v < 0 ? Color.fcRed : v > 0 ? Color.fcOK : Color.fcInk)
                    }
                }
            } header: { Text("Points") } footer: {
                Text("Running totals from every game you're playing (Stableford has its own table). For points and bragging rights only: Flagcast has no money in it. These game settings are kept on this phone.")
            }
        }
    }

    private func hasPointGames(_ r: SideResult) -> Bool {
        r.skins != nil || r.nassau != nil || r.birdies != nil || r.vegas != nil || r.wolf != nil || r.closest != nil || r.longDrive != nil
    }

    @ViewBuilder
    private func pickSection(_ title: String, _ toggle: String, _ g: Binding<SideConfig.Picks>, _ rows: [PickHole]?, _ r: SideResult,
                             _ nm: @escaping (String) -> String, empty: String, about: String) -> some View {
        Section {
            Toggle(toggle, isOn: g.on)
            if g.wrappedValue.on {
                amount("Each hole, from each player", g.amt)
                if let rows {
                    if rows.isEmpty { Text(empty).font(.footnote).foregroundStyle(Color.fcMuted) }
                    ForEach(rows, id: \.hole) { h in
                        Picker("Hole \(h.hole)", selection: Binding(get: { h.winner ?? "" }, set: { g.wrappedValue.picks["\(h.hole)"] = $0.isEmpty ? nil : $0 })) {
                            Text("Not yet").tag("")
                            ForEach(r.players, id: \.key) { p in Text(p.short).tag(p.key) }
                        }
                    }
                }
            }
        } header: { Text(title) } footer: { if !g.wrappedValue.on { Text(about) } }
    }

    private func amount(_ label: String, _ v: Binding<Double>) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                TextField("0", value: v, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    .onChange(of: v.wrappedValue) { _, x in if x < 0 || x > 1000 { v.wrappedValue = min(1000, max(0, x)) } }
                Text("pts").foregroundStyle(Color.fcMuted)
            }
            .font(.body.monospaced().weight(.semibold))
            .foregroundStyle(Color.fcInk)
            .frame(width: 96)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(Color.fcPaper2, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Points: \(label)")
        }
    }
    private func netPicker(_ v: Binding<Bool>) -> some View {
        Picker("Scoring", selection: v) { Text("Net (with strokes)").tag(true); Text("Gross").tag(false) }
            .tint(Color.fcInk)  // the chosen value: readable on light and dark
    }
    private func sidePicker(_ label: String, _ v: Binding<String>) -> some View {
        Picker(label, selection: v) { Text("Side A").tag("A"); Text("Side B").tag("B") }.tint(Color.fcInk)
    }
    private func holeChip(_ t: String, won: Bool, strong: Bool = false) -> some View {
        Text(t).font(.caption.monospaced()).padding(.horizontal, 7).padding(.vertical, 4)
            .background(won ? Color.fcPrimary : Color.fcPaper2, in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(won ? Color.fcOnGreen : strong ? Color.fcInk : Color.fcMuted)
    }
}

/// Points, without a trailing ".0" (a Nassau split three ways can leave a fraction).
func fmtPts(_ v: Double) -> String {
    let r = jsRound(v * 10) / 10
    return (r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)) + " pts"
}

/// One row per hole: who the wolf is, and the wolf's call.
private struct WolfPicks: View {
    @Bindable var model: ScorecardModel

    var body: some View {
        let r = model.sideResult()
        let P = Dictionary(uniqueKeysWithValues: (r?.players ?? []).map { ($0.key, $0.short) })
        func nm(_ k: String) -> String { P[k] ?? "" }
        return Form {
            Section {
                ForEach(r?.wolf?.holes ?? [], id: \.hole) { h in
                    Picker(selection: Binding(get: { h.partner ?? "" }, set: { model.side.wolf.picks["\(h.hole)"] = $0.isEmpty ? nil : $0 })) {
                        Text("Not yet").tag("")
                        ForEach((r?.players ?? []).filter { $0.key != h.wolf }, id: \.key) { p in Text("With \(p.short)").tag(p.key) }
                        Text("Lone wolf").tag("lone")
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hole \(h.hole): \(nm(h.wolf))")
                            if let res = h.result {
                                Text(res == "tie" ? "Halved" : res == "wolf" ? "Wolf won" : "Wolf lost")
                                    .font(.caption).foregroundStyle(res == "wolf" ? Color.fcOK : res == "others" ? Color.fcRed : Color.fcMuted)
                            }
                        }
                    }
                    .tint(Color.fcInk)
                }
            } footer: { Text("The wolf goes in cart order. Pick the wolf's call after the tee shots. The hole scores once everyone's score is in.") }
        }
        .navigationTitle("Wolf picks")
        .navigationBarTitleDisplayMode(.inline)
    }
}
