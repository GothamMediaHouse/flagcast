import SwiftUI

/// The cart's own side games: the same games and math as the web scorecard (core.js sideGames, checked by CoreTests).
/// The scores the cart enters play every game. Points only: Flagcast has no money in it. Settings stay on this phone.
///
/// One page with the points table, the games being played (with how each stands) and the games to add;
/// each game opens its own page for its settings, picks and hole by hole results. Every setting is a tap: no typing in a cart.

enum SideGame: String, CaseIterable, Identifiable, Hashable {
    case skins, nassau, birdies, stableford, vegas, wolf, closest, longDrive
    var id: String { rawValue }
    var title: String {
        switch self {
        case .skins: "Skins"; case .nassau: "Nassau"; case .birdies: "Birdies"; case .stableford: "Stableford"
        case .vegas: "Vegas"; case .wolf: "Wolf"; case .closest: "Closest to the pin"; case .longDrive: "Long drive"
        }
    }
    var icon: String {
        switch self {
        case .skins: "flag.fill"; case .nassau: "square.split.2x1.fill"; case .birdies: "bird.fill"; case .stableford: "list.number"
        case .vegas: "die.face.5.fill"; case .wolf: "pawprint.fill"; case .closest: "scope"; case .longDrive: "arrow.up.right"
        }
    }
    /// one line for the "add a game" tile
    var short: String {
        switch self {
        case .skins: "Lowest score alone wins the hole"
        case .nassau: "Front 9, back 9 and overall"
        case .birdies: "Every birdie collects"
        case .stableford: "Points against par"
        case .vegas: "Two against two, scores as numbers"
        case .wolf: "Pick a partner or go it alone"
        case .closest: "On the par 3s"
        case .longDrive: "On the par 5s"
        }
    }
    /// the rules, in plain words
    var rules: String {
        switch self {
        case .skins: "On each hole, the lowest score alone wins a skin, and everyone else gives the winner the points. When players tie, the skin can carry to the next hole."
        case .nassau: "Two sides play three matches: the front 9, the back 9 and the whole round. On each hole, the side with the best score wins the hole. The side ahead at the end of each match wins its points."
        case .birdies: "Each birdie collects the points from every other player in the cart. An eagle counts twice."
        case .stableford: "Points against par on every hole: double bogey or worse 0, bogey 1, par 2, birdie 3, eagle 4. Most points wins. These points have their own table."
        case .vegas: "Two against two. Each side's two scores make a number, low score first: a 4 and a 5 make 45. The lower number wins the difference in points."
        case .wolf: "The wolf rotates each hole, in cart order. After the tee shots, the wolf takes a partner or goes it alone. The best ball on each side wins the hole. A lone wolf plays for double."
        case .closest: "On each par 3, pick who finished closest to the pin. Everyone else gives them the points."
        case .longDrive: "On each par 5, pick who hit the longest drive in the fairway. Everyone else gives them the points."
        }
    }
    var minPlayers: Int { self == .wolf ? 3 : self == .vegas ? 4 : 2 }
    var needs: String? { self == .wolf ? "3 or 4 players" : self == .vegas ? "4 players" : nil }
    /// what the points setting means
    var stakeLabel: String? {
        switch self {
        case .skins: "A skin, from each player"; case .nassau: "Each match"; case .birdies: "A birdie, from each player"
        case .stableford: nil; case .vegas: "Each point of difference"; case .wolf: "Each hole"
        case .closest, .longDrive: "From each player"
        }
    }
}

extension SideConfig {
    func isOn(_ g: SideGame) -> Bool {
        switch g {
        case .skins: skins.on; case .nassau: nassau.on; case .birdies: birdies.on; case .stableford: stableford.on
        case .vegas: vegas.on; case .wolf: wolf.on; case .closest: closest.on; case .longDrive: longDrive.on
        }
    }
    mutating func set(_ g: SideGame, on: Bool) {
        switch g {
        case .skins: skins.on = on; case .nassau: nassau.on = on; case .birdies: birdies.on = on; case .stableford: stableford.on = on
        case .vegas: vegas.on = on; case .wolf: wolf.on = on; case .closest: closest.on = on; case .longDrive: longDrive.on = on
        }
    }
    func amt(_ g: SideGame) -> Double {
        switch g {
        case .skins: skins.amt; case .nassau: nassau.amt; case .birdies: birdies.amt; case .stableford: 0
        case .vegas: vegas.amt; case .wolf: wolf.amt; case .closest: closest.amt; case .longDrive: longDrive.amt
        }
    }
    mutating func set(_ g: SideGame, amt v: Double) {
        switch g {
        case .skins: skins.amt = v; case .nassau: nassau.amt = v; case .birdies: birdies.amt = v; case .stableford: break
        case .vegas: vegas.amt = v; case .wolf: wolf.amt = v; case .closest: closest.amt = v; case .longDrive: longDrive.amt = v
        }
    }
    func net(_ g: SideGame) -> Bool? {
        switch g {
        case .skins: skins.net; case .nassau: nassau.net; case .birdies: birdies.net; case .stableford: stableford.net
        case .vegas: vegas.net; case .wolf: wolf.net; case .closest, .longDrive: nil
        }
    }
    mutating func set(_ g: SideGame, net v: Bool) {
        switch g {
        case .skins: skins.net = v; case .nassau: nassau.net = v; case .birdies: birdies.net = v; case .stableford: stableford.net = v
        case .vegas: vegas.net = v; case .wolf: wolf.net = v; case .closest, .longDrive: break
        }
    }
}

/// Points, without a trailing ".0" (a Nassau split three ways can leave a fraction).
func fmtPts(_ v: Double, unit: Bool = true) -> String {
    let r = jsRound(v * 10) / 10
    return (r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)) + (unit ? (r == 1 ? " pt" : " pts") : "")
}

// MARK: - the hub

struct SideGamesHub: View {
    @Bindable var model: ScorecardModel
    @State private var open: SideGame?

    var body: some View {
        VStack(spacing: 0) {
            TourHeader(state: model.state, title: "Side games") { EmptyView() } below: {
                TourTitle(title: "Side games", sub: (model.sideResult()?.players.map(\.short).joined(separator: " · ") ?? "") + " · for points only")
            }
            ScrollView {
                if let r = model.sideResult() { hub(r) } else { ProgressView().padding(40) }
            }
        }
        .background(Color.fcPaper)
        .sheet(item: $open) { g in
            NavigationStack {
                SideGamePage(model: model, game: g)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { open = nil } } }
            }
            .tint(Color.fcPrimary)
        }
    }

    private func hub(_ r: SideResult) -> some View {
        let n = r.players.count
        let playing = SideGame.allCases.filter { model.side.isOn($0) }
        let others = SideGame.allCases.filter { !model.side.isOn($0) }
        return VStack(alignment: .leading, spacing: 22) {
            if n < 2 {
                VStack(spacing: 10) {
                    Image(systemName: "person.2.fill").font(.system(size: 34)).foregroundStyle(Color.fcMuted)
                    Text(n == 1 ? "You're the only player in your cart" : "Nobody is in your cart yet").font(.headline).multilineTextAlignment(.center)
                    Text("Side games need at least two players. They open up here once your cart has two or more.")
                        .font(.subheadline).foregroundStyle(Color.fcMuted).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).fcCard(padding: 24)
            } else {
                if playing.contains(where: { $0 != .stableford }) { standings(r) }

                if !playing.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Playing").fcLabel()
                        ForEach(playing) { g in
                            Button { open = g } label: { PlayingRow(game: g, status: status(g, r)) }.buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(playing.isEmpty ? "Pick a game" : "Add a game").fcLabel()
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(others) { g in
                            Button { open = g } label: { AddTile(game: g, tooFew: n < g.minPlayers || (g == .wolf && n > 4)) }.buttonStyle(.plain)
                        }
                    }
                }

                Text("The scores you enter play every game. For points and bragging rights only: Flagcast has no money in it. These settings stay on this phone.")
                    .font(.footnote).foregroundStyle(Color.fcMuted)
            }
        }
        .padding(16)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    /// everyone's running points from the games played for points (Stableford keeps its own table)
    private func standings(_ r: SideResult) -> some View {
        let rows = r.players.map { ($0, jsRound((r.ledger[$0.key] ?? 0) * 100) / 100) }.sorted { $0.1 > $1.1 }
        let top = rows.first?.1 ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Points").font(FCType.display(24)).textCase(.uppercase)
                Spacer()
                Text("All games").fcLabel()
            }
            .padding(.bottom, 8)
            ForEach(Array(rows.enumerated()), id: \.element.0.key) { i, row in
                let (p, v) = row
                HStack(spacing: 12) {
                    Text("\(i + 1)").font(.subheadline.monospacedDigit().weight(.semibold)).foregroundStyle(Color.fcMuted).frame(width: 18)
                    Text(p.short).font(.body.weight(.semibold))
                    if v > 0 && v == top { Image(systemName: "crown.fill").font(.caption).foregroundStyle(Color.fcFlag) }
                    Spacer()
                    Text(v == 0 ? "Even" : "\(v > 0 ? "+" : "−")\(fmtPts(abs(v), unit: false))")
                        .font(FCType.display(28)).monospacedDigit()
                        .foregroundStyle(v < 0 ? Color.fcRed : v > 0 ? Color.fcOK : Color.fcInk)
                }
                .padding(.vertical, 8)
                if i < rows.count - 1 { Divider().overlay(Color.fcLine) }
            }
        }
        .fcCard()
    }

    /// how a game stands, in a line
    private func status(_ g: SideGame, _ r: SideResult) -> String {
        let P = Dictionary(uniqueKeysWithValues: r.players.map { ($0.key, $0.short) })
        func nm(_ k: String) -> String { P[k] ?? "" }
        func leader(_ t: [String: Double]?) -> String? {
            guard let t, let best = t.max(by: { $0.value < $1.value }), best.value > 0 else { return nil }
            return "\(nm(best.key)) leads, +\(fmtPts(best.value))"
        }
        let tally = r.tally[g.rawValue]
        switch g {
        case .skins:
            guard let s = r.skins else { return "" }
            let won = s.won.values.reduce(0, +)
            if won == 0 && s.carrying == 0 { return "No skins won yet" }
            let best = s.won.max { $0.value < $1.value }
            return [best.map { "\(nm($0.key)) has \($0.value)" }, s.carrying > 0 ? "\(s.carrying) carrying" : nil].compactMap { $0 }.joined(separator: " · ")
        case .nassau:
            guard let na = r.nassau else { return "Put a player on each side" }
            let live = na.segs.first { $0.played > 0 && !$0.done } ?? na.segs.last { $0.done } ?? na.segs[0]
            let side = { (s: String) in (na.sides[s] ?? []).map(nm).joined(separator: " & ") }
            if live.played == 0 { return "Not started" }
            if live.diff == 0 { return "\(live.label): all square thru \(live.played)" }
            return "\(live.label): \(side(live.diff > 0 ? "A" : "B")) \(abs(live.diff)) up"
        case .birdies:
            let b = r.birdies ?? []
            return b.isEmpty ? "No birdies yet" : "\(b.count) so far · " + (leader(tally) ?? "")
        case .stableford:
            guard let top = r.stableford?.max(by: { $0.points < $1.points }), top.thru > 0 else { return "Not started" }
            return "\(nm(top.key)) leads with \(top.points) pts"
        case .vegas:
            if r.vegasNeedsFour { return r.players.count == 4 ? "Put two players on each side" : "Needs four players" }
            guard let v = r.vegas, !v.holes.isEmpty else { return "Not started" }
            let side = { (s: String) in (v.sides[s] ?? []).map(nm).joined(separator: " & ") }
            return v.total == 0 ? "All square" : "\(side(v.total > 0 ? "A" : "B")) +\(abs(v.total))"
        case .wolf:
            guard let w = r.wolf else { return "Needs three or four players" }
            if let next = w.holes.first(where: { $0.partner == nil }) { return "Hole \(next.hole): \(nm(next.wolf)) is the wolf" }
            return leader(tally) ?? "All holes picked"
        case .closest, .longDrive:
            let rows = (g == .closest ? r.closest : r.longDrive) ?? []
            let done = rows.filter { $0.winner != nil }.count
            return rows.isEmpty ? (g == .closest ? "No par 3s here" : "No par 5s here") : "\(done) of \(rows.count) holes picked" + (leader(tally).map { " · \($0)" } ?? "")
        }
    }
}

private struct GameIcon: View {
    let game: SideGame
    var on = true
    var body: some View {
        Image(systemName: game.icon)
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 38, height: 38)
            .background(on ? Color.fcPrimary : Color.fcPaper2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(on ? Color.white : Color.fcInk)
    }
}

private struct PlayingRow: View {
    let game: SideGame, status: String
    var body: some View {
        HStack(spacing: 12) {
            GameIcon(game: game)
            VStack(alignment: .leading, spacing: 2) {
                Text(game.title).font(.body.weight(.semibold)).foregroundStyle(Color.fcInk)
                Text(status).font(.subheadline).foregroundStyle(Color.fcMuted).lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.fcMuted)
        }
        .fcCard(padding: 12)
        .contentShape(Rectangle())
    }
}

private struct AddTile: View {
    let game: SideGame, tooFew: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                GameIcon(game: game, on: false)
                Spacer()
                Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(tooFew ? Color.fcLine : Color.fcPrimary)
            }
            Text(game.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.fcInk).lineLimit(1).minimumScaleFactor(0.8)
            Text(tooFew ? "Needs \(game.needs ?? "more players")" : game.short)
                .font(.caption).foregroundStyle(Color.fcMuted).lineLimit(2, reservesSpace: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fcCard(padding: 12)
        .opacity(tooFew ? 0.6 : 1)
        .contentShape(Rectangle())
    }
}

// MARK: - one game's page

private struct SideGamePage: View {
    @Bindable var model: ScorecardModel
    let game: SideGame

    var body: some View {
        let r = model.sideResult()
        let n = r?.players.count ?? 0
        let on = model.side.isOn(game)
        let canPlay = n >= game.minPlayers && !(game == .wolf && n > 4)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    GameIcon(game: game, on: on)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(game.title).fcHeading(.title3)
                        Text(on ? "Playing" : "Not playing").fcLabel()
                    }
                }
                Text(game.rules).font(.subheadline).foregroundStyle(Color.fcMuted).fixedSize(horizontal: false, vertical: true)

                if !canPlay {
                    Label("This game needs \(game.needs ?? "more players"). Your cart has \(n).", systemImage: "person.2")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading).fcCard(padding: 14)
                } else {
                    settings
                    if on, let r { results(r) }
                }

                if canPlay || on {
                    Button {
                        withAnimation { model.side.set(game, on: !on) }
                    } label: { Label(on ? "Stop playing \(game.title)" : "Play \(game.title)", systemImage: on ? "xmark" : "play.fill") }
                        .buttonStyle(on ? .fcDanger : .fcPrimary)
                }
            }
            .padding(16)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Color.fcPaper.ignoresSafeArea())
        .navigationTitle(game.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // ---- settings: all taps ----
    @ViewBuilder private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let label = game.stakeLabel {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Points").fcLabel()
                        Text(label).font(.subheadline)
                    }
                    Spacer()
                    Stepper(value: Binding(get: { model.side.amt(game) }, set: { model.side.set(game, amt: max(0, min(100, $0))) }), in: 0...100, step: 1) {
                        Text(fmtPts(model.side.amt(game))).font(FCType.display(28)).monospacedDigit()
                    }
                    .fixedSize()
                }
            }
            if let net = model.side.net(game) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Scoring").fcLabel()
                    Picker("Scoring", selection: Binding(get: { net }, set: { model.side.set(game, net: $0) })) {
                        Text("Net (with strokes)").tag(true); Text("Gross").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
            }
            if game == .skins {
                Toggle(isOn: Binding(get: { model.side.skins.carry != false }, set: { model.side.skins.carry = $0 })) {
                    Text("Ties carry to the next hole").font(.subheadline)
                }
                .tint(Color.fcPrimary)
            }
        }
        .fcCard()
    }

    // ---- results and picks ----
    @ViewBuilder private func results(_ r: SideResult) -> some View {
        let P = Dictionary(uniqueKeysWithValues: r.players.map { ($0.key, $0.short) })
        let nm = { (k: String) in P[k] ?? "" }
        switch game {
        case .skins:
            if let sk = r.skins {
                card("Holes") {
                    FlowLayout(spacing: 6) {
                        ForEach(sk.rows, id: \.hole) { row in
                            switch row {
                            case let .won(h, w, _, worth): HoleChip(hole: h, text: nm(w) + (worth > 1 ? " ×\(worth)" : ""), style: .won)
                            case let .tied(h, _, _, _): HoleChip(hole: h, text: "Tie", style: .tie)
                            case let .open(h, _): HoleChip(hole: h, text: nil, style: .open)
                            }
                        }
                    }
                    if sk.carrying > 0 { Text("\(sk.carrying) skin\(sk.carrying > 1 ? "s" : "") carrying to the next hole.").font(.footnote).foregroundStyle(Color.fcMuted) }
                }
                tallyCard(r, extra: { k in "\(sk.won[k] ?? 0) skins" })
            }
        case .nassau:
            sidesCard(r, current: r.nassau?.sides, saved: model.side.nassau.sides, set: { k, s in model.side.nassau.sides[k] = s })
            if let na = r.nassau {
                let side = { (s: String) in (na.sides[s] ?? []).map(nm).joined(separator: " & ") }
                card("Matches") {
                    ForEach(na.segs, id: \.label) { g in
                        HStack {
                            Text(g.label).font(.body.weight(.semibold))
                            Spacer()
                            Text(g.played == 0 ? "Not started"
                                 : g.done ? (g.winner.map { "\(side($0)) win, \(abs(g.diff)) up" } ?? "Tied")
                                 : g.diff != 0 ? "\(side(g.diff > 0 ? "A" : "B")) \(abs(g.diff)) up thru \(g.played)" : "All square thru \(g.played)")
                                .font(.subheadline).foregroundStyle(Color.fcMuted).multilineTextAlignment(.trailing)
                        }
                        .padding(.vertical, 4)
                    }
                }
                tallyCard(r)
            }
        case .birdies:
            card("Birdies") {
                if let b = r.birdies, !b.isEmpty {
                    FlowLayout(spacing: 6) { ForEach(Array(b.enumerated()), id: \.offset) { _, x in HoleChip(hole: x.hole, text: nm(x.key) + (x.eagle ? " eagle" : ""), style: .won) } }
                } else { Text("No birdies yet.").font(.subheadline).foregroundStyle(Color.fcMuted) }
            }
            tallyCard(r)
        case .stableford:
            if let sf = r.stableford {
                card("Table") {
                    ForEach(Array(sf.sorted { $0.points > $1.points }.enumerated()), id: \.element.key) { i, row in
                        HStack {
                            Text("\(i + 1)").font(.subheadline.monospacedDigit()).foregroundStyle(Color.fcMuted).frame(width: 18)
                            Text(nm(row.key)).font(.body.weight(.semibold))
                            Spacer()
                            Text(row.thru == 0 ? "–" : "thru \(row.thru)").font(.caption).foregroundStyle(Color.fcMuted)
                            Text("\(row.points)").font(FCType.display(28)).monospacedDigit().frame(minWidth: 36, alignment: .trailing)
                        }
                    }
                }
            }
        case .vegas:
            if r.players.count == 4 { sidesCard(r, current: r.vegas?.sides, saved: model.side.vegas.sides, set: { k, s in model.side.vegas.sides[k] = s }) }
            if let v = r.vegas, !r.vegasNeedsFour {
                let side = { (s: String) in (v.sides[s] ?? []).map(nm).joined(separator: " & ") }
                card("Holes") {
                    if v.holes.isEmpty { Text("No holes finished yet.").font(.subheadline).foregroundStyle(Color.fcMuted) }
                    else {
                        FlowLayout(spacing: 6) { ForEach(v.holes, id: \.hole) { h in HoleChip(hole: h.hole, text: "\(h.a)–\(h.b)", style: h.a == h.b ? .tie : .won) } }
                        Text(v.total == 0 ? "All square" : "\(side(v.total > 0 ? "A" : "B")) are up \(abs(v.total))").font(.body.weight(.semibold))
                    }
                }
                tallyCard(r)
            } else if r.players.count == 4 {
                Text("Put two players on each side.").font(.subheadline).foregroundStyle(Color.fcMuted)
            }
        case .wolf:
            if let w = r.wolf {
                card("The wolf's call") {
                    ForEach(w.holes, id: \.hole) { h in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Hole \(h.hole)").font(.subheadline.weight(.semibold))
                                Text("\(nm(h.wolf)) is the wolf").font(.subheadline).foregroundStyle(Color.fcMuted)
                                Spacer()
                                if let res = h.result {
                                    Text(res == "tie" ? "Halved" : res == "wolf" ? "Wolf won" : "Wolf lost").font(.caption.weight(.semibold))
                                        .foregroundStyle(res == "wolf" ? Color.fcOK : res == "others" ? Color.fcRed : Color.fcMuted)
                                }
                            }
                            FlowLayout(spacing: 6) {
                                ForEach(r.players.filter { $0.key != h.wolf }, id: \.key) { p in
                                    Chip(title: "+ \(p.short)", on: h.partner == p.key) { pick(\.wolf, h.hole, p.key, current: h.partner) }
                                }
                                Chip(title: "Alone", on: h.partner == "lone") { pick(\.wolf, h.hole, "lone", current: h.partner) }
                            }
                        }
                        .padding(.vertical, 6)
                        if h.hole != w.holes.last?.hole { Divider().overlay(Color.fcLine) }
                    }
                }
                tallyCard(r)
            }
        case .closest, .longDrive:
            let rows = (game == .closest ? r.closest : r.longDrive) ?? []
            let kp: WritableKeyPath<SideConfig, SideConfig.Picks> = game == .closest ? \.closest : \.longDrive
            card(game == .closest ? "Who was closest" : "Who hit it longest") {
                if rows.isEmpty { Text(game == .closest ? "This course has no par 3s." : "This course has no par 5s.").font(.subheadline).foregroundStyle(Color.fcMuted) }
                ForEach(rows, id: \.hole) { h in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hole \(h.hole)").font(.subheadline.weight(.semibold))
                        FlowLayout(spacing: 6) {
                            ForEach(r.players, id: \.key) { p in Chip(title: p.short, on: h.winner == p.key) { pick(kp, h.hole, p.key, current: h.winner) } }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            tallyCard(r)
        }
    }

    /// tap a chip to pick, tap it again to clear
    private func pick(_ kp: WritableKeyPath<SideConfig, SideConfig.Picks>, _ hole: Int, _ v: String, current: String?) {
        withAnimation(.easeOut(duration: 0.15)) { model.side[keyPath: kp].picks["\(hole)"] = current == v ? nil : v }
    }

    private func card<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(title).fcLabel(); c() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fcCard()
    }

    /// this game's own points
    private func tallyCard(_ r: SideResult, extra: ((String) -> String)? = nil) -> some View {
        let t = r.tally[game.rawValue] ?? [:]
        return card("Points in this game") {
            ForEach(r.players.sorted { (t[$0.key] ?? 0) > (t[$1.key] ?? 0) }, id: \.key) { p in
                let v = jsRound((t[p.key] ?? 0) * 100) / 100
                HStack {
                    Text(p.short).font(.body.weight(.semibold))
                    if let extra { Text(extra(p.key)).font(.caption).foregroundStyle(Color.fcMuted) }
                    Spacer()
                    Text(v == 0 ? "Even" : "\(v > 0 ? "+" : "−")\(fmtPts(abs(v)))").font(.body.monospacedDigit().weight(.semibold))
                        .foregroundStyle(v < 0 ? Color.fcRed : v > 0 ? Color.fcOK : Color.fcInk)
                }
            }
        }
    }

    /// Side A and Side B: tap a player to move them across
    private func sidesCard(_ r: SideResult, current: [String: [String]]?, saved: [String: String], set: @escaping (String, String) -> Void) -> some View {
        let A = Set(current?["A"] ?? [])
        // the game works the sides out (by team, or half and half) unless a side is empty: then show what's saved
        func inA(_ k: String) -> Bool { current == nil ? saved[k] != "B" : A.contains(k) }
        return card("Sides · tap a player to switch") {
            HStack(alignment: .top, spacing: 10) {
                ForEach(["A", "B"], id: \.self) { s in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Side \(s)").font(.subheadline.weight(.semibold)).foregroundStyle(Color.fcMuted)
                        ForEach(r.players.filter { inA($0.key) == (s == "A") }, id: \.key) { p in
                            Button { withAnimation(.easeOut(duration: 0.15)) { set(p.key, s == "A" ? "B" : "A") } } label: {
                                HStack {
                                    Text(p.short).font(.body.weight(.semibold))
                                    Spacer()
                                    Image(systemName: s == "A" ? "arrow.right" : "arrow.left").font(.caption.weight(.bold)).foregroundStyle(Color.fcMuted)
                                }
                                .padding(.horizontal, 12).frame(minHeight: 40)
                                .background(Color.fcPaper2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct HoleChip: View {
    enum Style { case won, tie, open }
    let hole: Int, text: String?, style: Style
    var body: some View {
        HStack(spacing: 4) {
            Text("\(hole)").font(.caption.monospacedDigit().weight(.bold))
            if let text { Text(text).font(.caption) }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(style == .won ? Color.fcPrimary : Color.fcPaper2, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .foregroundStyle(style == .won ? Color.white : style == .tie ? Color.fcInk : Color.fcMuted)
    }
}
