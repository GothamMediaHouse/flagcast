import Foundation

// The scoring math, ported line for line from public/golf/core.js so the app shows exactly the numbers the
// website, the big screens and the Manager show. FlagcastTests checks this against core.js on the same input
// (tools/make-core-fixture.mjs writes the fixture), so change both together.

/// JavaScript's Math.round: halves round up (toward +infinity), also for negative numbers.
@inline(__always) func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

extension Array {
    /// A stable sort, like JavaScript's Array.prototype.sort: equal elements keep their order.
    func stableSorted(by less: (Element, Element) -> Bool) -> [Element] {
        enumerated().sorted { a, b in
            if less(a.element, b.element) { return true }
            if less(b.element, a.element) { return false }
            return a.offset < b.offset
        }.map(\.element)
    }
}

struct CardRow: Hashable { var hole: Int, par: Int, gross: Int?, net: Int?, done: Bool, off: Bool = false }

struct Entry: Hashable {
    var key: String, teamId: String, name: String, sub: String, flight: String, start: Int, team: Team
}

struct Line: Hashable, Identifiable {
    var entry: Entry
    var card: [CardRow]
    var played = 0, total = 0, toPar = 0, nr = false, score = 0
    var pos = "", thru = ""
    var id: String { entry.key }
    var key: String { entry.key }
    var teamId: String { entry.teamId }
    var name: String { entry.name }
    var sub: String { entry.sub }
    var flight: String { entry.flight }
    var team: Team { entry.team }
}

struct HoleStats: Hashable {
    var holeNo: Int, par: Int, eagle = 0, birdie = 0, par0 = 0, bogey = 0, worse = 0
    var aces: [Who] = [], n = 0, total = 0
    var avg: Double?
}
struct Who: Hashable { var name: String, team: String }

enum SkinRow: Hashable {
    case open(hole: Int)
    case won(hole: Int, who: Who, score: Int, worth: Int)
    case tied(hole: Int, count: Int, score: Int)
    var hole: Int { switch self { case .open(let h), .won(let h, _, _, _), .tied(let h, _, _): return h } }
}

enum Mark: String { case none = "", eagle, birdie, bogey, double }

// ---- side games ----
/// A cart's side-game settings. A missing field reads as JavaScript would read it (falsy), so a saved or
/// fixture config means the same thing here as on the website.
struct SideConfig: Codable, Hashable {
    struct Game: Codable, Hashable {
        var on = false, amt: Double = 0, net = true, carry: Bool? = nil
        init(on: Bool = false, amt: Double = 0, net: Bool = true, carry: Bool? = nil) { self.on = on; self.amt = amt; self.net = net; self.carry = carry }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            on = c.bool(.on, false); amt = c.dbl(.amt, 0); net = c.bool(.net, false); carry = try? c.decodeIfPresent(Bool.self, forKey: .carry)
        }
    }
    struct Nassau: Codable, Hashable {
        var on = false, amt: Double = 10, net = true, sides: [String: String] = [:]
        init() {}
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            on = c.bool(.on, false); amt = c.dbl(.amt, 0); net = c.bool(.net, false)
            sides = (try? c.decodeIfPresent([String: String].self, forKey: .sides)) ?? [:]
        }
    }
    /// A game the cart scores with a pick on some holes (the wolf's partner, who was closest, who hit it longest).
    /// `picks` maps a hole number ("7") to a player key, or to "lone" for a lone wolf, or "none" when nobody won it.
    struct Picks: Codable, Hashable {
        var on = false, amt: Double = 1, net = true, picks: [String: String] = [:], sides: [String: String] = [:]
        init(on: Bool = false, amt: Double = 1, net: Bool = true) { self.on = on; self.amt = amt; self.net = net }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            on = c.bool(.on, false); amt = c.dbl(.amt, 1); net = c.bool(.net, true)
            picks = (try? c.decodeIfPresent([String: String].self, forKey: .picks)) ?? [:]
            sides = (try? c.decodeIfPresent([String: String].self, forKey: .sides)) ?? [:]
        }
    }
    var skins = Game(on: false, amt: 5, net: true, carry: true)
    var nassau = Nassau()
    var birdies = Game(on: false, amt: 2, net: false)
    // the newer games (the web scorecard has them too)
    var stableford = Picks(on: false, amt: 1, net: true)
    var vegas = Picks(on: false, amt: 1, net: true)
    var wolf = Picks(on: false, amt: 1, net: true)
    var closest = Picks(on: false, amt: 2, net: false)
    var longDrive = Picks(on: false, amt: 2, net: false)
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        skins = (try? c.decodeIfPresent(Game.self, forKey: .skins)) ?? Game()
        nassau = (try? c.decodeIfPresent(Nassau.self, forKey: .nassau)) ?? { var n = Nassau(); n.amt = 0; n.net = false; return n }()
        birdies = (try? c.decodeIfPresent(Game.self, forKey: .birdies)) ?? Game()
        stableford = (try? c.decodeIfPresent(Picks.self, forKey: .stableford)) ?? Picks(net: true)
        vegas = (try? c.decodeIfPresent(Picks.self, forKey: .vegas)) ?? Picks(net: true)
        wolf = (try? c.decodeIfPresent(Picks.self, forKey: .wolf)) ?? Picks(net: true)
        closest = (try? c.decodeIfPresent(Picks.self, forKey: .closest)) ?? Picks(amt: 2, net: false)
        longDrive = (try? c.decodeIfPresent(Picks.self, forKey: .longDrive)) ?? Picks(amt: 2, net: false)
    }
    var anyOn: Bool { skins.on || nassau.on || birdies.on || stableford.on || vegas.on || wolf.on || closest.on || longDrive.on }
}

struct SidePlayer: Hashable { var key: String, id: String, team: String, name: String, hcp: Int, short: String }
enum SideSkinRow: Hashable {
    case open(hole: Int, pot: Int)
    case won(hole: Int, winner: String, score: Int, worth: Int)
    case tied(hole: Int, count: Int, score: Int?, pot: Int)
    var hole: Int { switch self { case .open(let h, _), .won(let h, _, _, _), .tied(let h, _, _, _): return h } }
}
struct SideSkins: Hashable { var rows: [SideSkinRow]; var won: [String: Int]; var carrying: Int }
struct NassauSeg: Hashable { var label: String, played: Int, holes: Int, diff: Int, done: Bool, winner: String? }
struct SideNassau: Hashable { var sides: [String: [String]]; var segs: [NassauSeg] }
struct BirdieHit: Hashable { var key: String, hole: Int, count: Int, eagle: Bool }
struct Settle: Hashable { var from: String, to: String, amt: Double }
struct StablefordRow: Hashable { var key: String, points: Int, thru: Int }
/// Vegas: each side's two scores make a number, low score first (a 4 and a 5 make 45). Points are the difference.
struct VegasHole: Hashable { var hole: Int, a: Int, b: Int }
struct SideVegas: Hashable { var sides: [String: [String]]; var holes: [VegasHole]; var total: Int }
/// Wolf: the wolf rotates each hole. `partner` is a player key, "lone", or nil until the cart picks.
struct WolfHole: Hashable { var hole: Int, wolf: String, partner: String?, result: String? }  // result: "wolf", "others", "tie"
struct SideWolf: Hashable { var holes: [WolfHole] }
struct PickHole: Hashable { var hole: Int, winner: String? }
struct SideResult: Hashable {
    var players: [SidePlayer]
    var ledger: [String: Double]
    var settle: [Settle] = []
    var skins: SideSkins?
    var nassau: SideNassau?
    var birdies: [BirdieHit]?
    var stableford: [StablefordRow]?
    var vegas: SideVegas?
    var vegasNeedsFour = false
    var wolf: SideWolf?
    var closest: [PickHole]?
    var longDrive: [PickHole]?
    /// each game's own points per player (the ledger is the sum of these, Stableford aside)
    var tally: [String: [String: Double]] = [:]
}

enum Core {
    static func defaultHoles() -> [Hole] {
        let par = [4, 5, 4, 3, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4, 4, 3, 4, 5]
        let hcp = [7, 3, 11, 15, 1, 9, 17, 5, 13, 8, 16, 2, 4, 12, 10, 18, 6, 14]
        let yds = [3: 165, 4: 385, 5: 520]
        return par.enumerated().map { i, p in Hole(n: i + 1, par: p, yds: yds[p] ?? 0, hcp: hcp[i]) }
    }

    /// Strokes a player with this playing handicap gets on a hole with this stroke index (plus handicaps give strokes back).
    static func strokesOn(_ h: Int, _ si: Int) -> Int {
        if h == 0 { return 0 }
        if h > 0 { return h / 18 + (si <= h % 18 ? 1 : 0) }
        let p = -h
        return -(p / 18 + (si > 18 - (p % 18) ? 1 : 0))
    }

    /// GHIN Handicap Index as written on a card: plus handicaps are negative here (+2.1 → -2.1), so show them with a +.
    static func fmtIndex(_ n: Double?) -> String {
        guard let n else { return "" }
        let s = n == n.rounded() ? String(Int(abs(n))) : String(format: "%.1f", abs(n))
        return n < 0 ? "+" + s : s
    }

    static func playing(_ hcp: Double, _ allowance: Double) -> Int {
        let v = jsRound(hcp * allowance / 100)
        return v.isFinite ? Int(v) : 0
    }

    private static func isScore(_ v: Int?) -> Bool { (v ?? -1) >= 0 }
    private static func at(_ arr: [Int?]?, _ i: Int) -> Int? { guard let a = arr, i < a.count else { return nil }; return a[i] }

    /// The holes the round is played on: all 18, the front 9 (1–9) or the back 9 (10–18), from format.nine.
    static func playHoles(_ ev: EventState) -> [Int] {
        switch ev.format.nine { case "front": return Array(1...9); case "back": return Array(10...18); default: return Array(1...18) }
    }

    /// One team's card, hole by hole: what counts on each hole for this format.
    static func teamCard(_ ev: EventState, _ team: Team, _ sc: [String: [Int?]]?) -> [CardRow] {
        let f = ev.format, holes = ev.course.holes, allow = f.allowance
        let type = f.type
        let count = type == "stroke" ? 1 : max(1, min(4, f.count == 0 ? 1 : f.count))
        let s = sc ?? [:]
        var rows: [CardRow] = []
        let inPlay = Set(playHoles(ev))
        for i in 0..<18 {
            let hole = holes[i]
            if !inPlay.contains(i + 1) { rows.append(CardRow(hole: hole.n, par: hole.par, gross: nil, net: nil, done: false, off: true)); continue }
            var gross: Int? = nil, net: Int? = nil, done = false, parFor = hole.par
            if type == "scramble" {
                if let v = at(s["T"], i) {
                    done = true
                    let st = strokesOn(playing(team.hcp, allow), hole.hcp)
                    if v > 0 { gross = v; net = v - st } else { gross = hole.par + 2 + st; net = hole.par + 2 }
                }
            } else {
                let ps = team.players
                let entered = ps.map { at(s[$0.id], i) }
                done = !ps.isEmpty && entered.allSatisfy { $0 != nil }
                if done {
                    struct E { var g: Int, n: Int, pts: Int, gpts: Int }
                    let each: [E] = ps.enumerated().map { k, p in
                        let v = entered[k]!
                        let st = strokesOn(playing(p.hcp, allow), hole.hcp)
                        // picked up: counts as net double bogey, and 0 Stableford points
                        if v <= 0 { return E(g: hole.par + 2 + st, n: hole.par + 2, pts: 0, gpts: 0) }
                        let n = v - st
                        return E(g: v, n: n, pts: max(0, 2 + hole.par - n), gpts: max(0, 2 + hole.par - v))
                    }
                    let take = min(count, each.count)
                    if type == "stableford" {
                        let pts = each.map(\.pts).sorted(by: >).prefix(take).reduce(0, +)
                        let gp = each.map(\.gpts).sorted(by: >).prefix(take).reduce(0, +)
                        gross = gp; net = pts
                    } else if take == count {
                        gross = each.map(\.g).sorted().prefix(take).reduce(0, +)
                        net = each.map(\.n).sorted().prefix(take).reduce(0, +)
                    }
                    parFor = hole.par * count
                }
            }
            rows.append(CardRow(hole: hole.n, par: parFor, gross: gross, net: net, done: done))
        }
        return rows
    }

    private static func last(_ n: String) -> String {
        n.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
    }

    /// Every line on the leaderboard (a stroke play event lists players, the rest list teams).
    static func entries(_ ev: EventState) -> [Entry] {
        if ev.format.type == "stroke" {
            return ev.teams.flatMap { t in
                t.players.map { p in
                    var one = t; one.players = [p]
                    return Entry(key: "\(t.id):\(p.id)", teamId: t.id, name: p.name, sub: t.name, flight: t.flight, start: t.start == 0 ? 1 : t.start, team: one)
                }
            }
        }
        return ev.teams.map { t in
            Entry(key: t.id, teamId: t.id, name: t.name.isEmpty ? t.players.map { last($0.name) }.joined(separator: " / ") : t.name,
                  sub: t.players.map(\.name).joined(separator: ", "), flight: t.flight, start: t.start == 0 ? 1 : t.start, team: t)
        }
    }

    /// The leaderboard: sorted, with positions (ties shown as T2) and holes played.
    static func leaderboard(_ ev: EventState, _ scores: Scores, flight: String? = nil, mode: String? = nil) -> [Line] {
        let f = ev.format, stab = f.type == "stableford"
        let mode = mode ?? (f.show.isEmpty ? "net" : f.show)
        let lines: [Line] = entries(ev).map { e in
            let sc = scores[e.teamId] ?? [:]
            let card: [CardRow]
            if f.type == "stroke" { let pid = e.team.players[0].id; card = teamCard(ev, e.team, [pid: sc[pid] ?? []]) }
            else { card = teamCard(ev, e.team, sc) }
            var l = Line(entry: e, card: card)
            for r in card where r.done {
                l.played += 1
                guard let v = mode == "gross" ? r.gross : r.net else { l.nr = !stab; continue }
                l.total += v
                if !stab { l.toPar += v - r.par }
            }
            l.score = stab ? l.total : l.toPar
            return l
        }
        let ph = playHoles(ev), full = ph.count, endH = ph[full - 1]
        let filtered0 = (flight?.isEmpty == false) ? lines.filter { $0.flight == flight } : lines
        func back(_ l: Line, _ from: Int) -> Int {
            l.card[(from - 1)...].reduce(0) { t, r in t + (r.done ? ((mode == "gross" ? r.gross : r.net) ?? 0) - (stab ? 0 : r.par) : 0) }
        }
        // the JS comparator, as a three-way compare
        func cmp(_ a: Line, _ b: Line) -> Int {
            if (a.played == 0) != (b.played == 0) { return a.played > 0 ? -1 : 1 }
            if a.nr != b.nr { return a.nr ? 1 : -1 }
            let d = stab ? b.score - a.score : a.score - b.score
            if d != 0 { return d }
            if a.played == full && b.played == full {
                for from in (full == 18 ? [10, 13, 16, 18] : [endH - 5, endH - 2, endH]) {
                    let x = back(a, from), y = back(b, from)
                    if x != y { return stab ? y - x : x - y }
                }
            }
            if b.played != a.played { return b.played - a.played }
            switch a.name.localizedCompare(b.name) { case .orderedAscending: return -1; case .orderedDescending: return 1; default: return 0 }
        }
        var filtered = filtered0.stableSorted { cmp($0, $1) < 0 }
        var pos = 0
        func tied(_ o: Line?, _ l: Line) -> Bool { guard let o else { return false }; return o.played > 0 && l.played > 0 && o.nr == l.nr && o.score == l.score }
        for i in filtered.indices {
            let l = filtered[i]
            let prev = i > 0 ? filtered[i - 1] : nil, next = i + 1 < filtered.count ? filtered[i + 1] : nil
            if !tied(prev, l) { pos = i + 1 }
            filtered[i].pos = l.played > 0 ? (tied(prev, l) || tied(next, l) ? "T\(pos)" : String(pos)) : ""
            filtered[i].thru = l.played == full ? "F" : l.played > 0 ? String(l.played) : (l.entry.start != 1 ? "Starts \(l.entry.start)" : "—")
        }
        return filtered
    }

    /// What the course map's group card shows about one group (public/golf/core.js groupInfo): its players, holes
    /// played, score and place. Stroke play has a line per player: the group's score and place are its best player's.
    struct GroupInfo { var name: String, thru: String, score: String, pos: String, players: [(id: String, name: String, hcp: Double, today: String)] }
    static func groupInfo(_ ev: EventState, _ scores: Scores, _ teamId: String) -> GroupInfo? {
        guard let team = ev.teams.first(where: { $0.id == teamId }) else { return nil }
        let stab = ev.format.type == "stableford", lines = leaderboard(ev, scores).filter { $0.teamId == teamId }
        let best = lines.first { $0.played > 0 } ?? lines.first, per = lines.count > 1
        let players = team.players.map { p -> (id: String, name: String, hcp: Double, today: String) in
            if per, let l = lines.first(where: { $0.key == "\(teamId):\(p.id)" }), l.played > 0 { return (p.id, p.name, p.hcp, fmtPar(l.score, stab)) }
            // otherwise their own gross score to par over the holes they've finished
            var d = 0, n = 0
            for (i, v) in (scores[teamId]?[p.id] ?? []).enumerated() { if let v, v > 0 { d += v - (i < ev.course.holes.count ? ev.course.holes[i].par : 4); n += 1 } }
            return (p.id, p.name, p.hcp, n > 0 && ev.format.type != "scramble" ? "\(fmtPar(d)) gross" : "")
        }
        return GroupInfo(name: best.map { per ? (team.name.isEmpty ? $0.entry.sub : team.name) : $0.name } ?? team.name,
                         thru: best?.thru ?? "—", score: best.map { $0.played > 0 ? fmtPar($0.score, stab) : "—" } ?? "—",
                         pos: best.map { $0.pos.isEmpty ? "—" : $0.pos } ?? "—", players: players)
    }

    static func fmtPar(_ n: Int, _ stab: Bool = false) -> String {
        if stab { return "\(n) pts" }
        if n == 0 { return "E" }
        return n > 0 ? "+\(n)" : "−\(-n)"
    }

    /// How a single hole went for everyone, for the par 3 pages.
    static func holeStats(_ ev: EventState, _ scores: Scores, _ holeNo: Int) -> HoleStats {
        let i = holeNo - 1, par = ev.course.holes[i].par
        var out = HoleStats(holeNo: holeNo, par: par)
        for t in ev.teams {
            let sc = scores[t.id] ?? [:]
            let who = ev.format.isScramble ? [Player(id: "T", name: t.name)] : t.players
            for p in who {
                guard let v = at(sc[p.id], i), v > 0 else { continue }
                out.n += 1; out.total += v
                let d = v - par
                if v == 1 { out.aces.append(Who(name: p.name, team: t.name)) }
                if d <= -2 { out.eagle += 1 } else if d == -1 { out.birdie += 1 } else if d == 0 { out.par0 += 1 } else if d == 1 { out.bogey += 1 } else { out.worse += 1 }
            }
        }
        out.avg = out.n > 0 ? Double(out.total) / Double(out.n) : nil
        return out
    }

    /// Gross skins across the whole field: a hole is won when one player has the lowest score alone; ties carry over.
    static func skins(_ ev: EventState, _ scores: Scores, carry: Bool = true) -> [SkinRow] {
        if ev.format.isScramble { return [] }
        var res: [SkinRow] = [], pot = 1
        for i in 0..<18 {
            var best = Int.max, who: [Who] = [], all = true
            for t in ev.teams { for p in t.players {
                let v = at(scores[t.id]?[p.id], i)
                guard let v else { all = false; continue }
                if v <= 0 { continue }
                if v < best { best = v; who = [Who(name: p.name, team: t.name)] } else if v == best { who.append(Who(name: p.name, team: t.name)) }
            } }
            if !all || who.isEmpty { res.append(.open(hole: i + 1)); pot = 1; continue }
            if who.count == 1 { res.append(.won(hole: i + 1, who: who[0], score: best, worth: pot)); pot = 1 }
            else { res.append(.tied(hole: i + 1, count: who.count, score: best)); pot = carry ? pot + 1 : 1 }
        }
        return res
    }

    /// Contest standings: closest to the pin (shortest wins) and long drive (longest wins).
    static func contestLeader(_ c: Contest) -> [ContestEntry] {
        let list = c.entries.filter { !$0.name.isEmpty && $0.dist > 0 }
        return c.isLongDrive ? list.stableSorted { $0.dist > $1.dist } : list.stableSorted { $0.dist < $1.dist }
    }

    static func fmtDist(_ c: Contest, _ d: Double) -> String {
        if c.isLongDrive { return "\(Int(jsRound(d))) yds" }
        let inches = Int(jsRound(d * 12)), ft = inches / 12, inch = inches % 12
        return "\(ft) ft \(inch) in"
    }

    /// The scorecard mark: circle for birdie, double circle for eagle or better, square for bogey, double square worse.
    static func mark(_ v: Int?, _ par: Int) -> Mark {
        guard let v, v > 0 else { return .none }
        let d = v - par
        return d <= -2 ? .eagle : d == -1 ? .birdie : d == 1 ? .bogey : d >= 2 ? .double : .none
    }

    private static func first(_ n: String) -> String {
        n.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
    }

    /// A cart's own side games, scored in points (no money), with each player's running total. Same math as core.js sideGames.
    static func sideGames(_ ev: EventState, _ scores: Scores, _ teamIds: [String], _ cfg: SideConfig) -> SideResult {
        let allow = ev.format.allowance, holes = ev.course.holes
        let teams = teamIds.compactMap { id in ev.teams.first { $0.id == id } }
        var players: [SidePlayer] = []
        for t in teams { for p in t.players {
            players.append(SidePlayer(key: "\(t.id):\(p.id)", id: p.id, team: t.id, name: p.name.isEmpty ? "Player" : p.name, hcp: playing(p.hcp, allow), short: ""))
        } }
        for k in players.indices {
            let p = players[k]
            let same = players.filter { first($0.name) == first(p.name) }.count > 1
            let parts = p.name.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace).map(String.init)
            players[k].short = same && parts.count > 1 ? "\(parts[0]) \(parts[parts.count - 1].prefix(1))." : first(p.name)
        }
        func raw(_ p: SidePlayer, _ i: Int) -> Int? { at(scores[p.team]?[p.id], i) }
        func entered(_ p: SidePlayer, _ i: Int) -> Bool { raw(p, i) != nil }
        func val(_ p: SidePlayer, _ i: Int, _ net: Bool) -> Int {
            let v = raw(p, i), st = strokesOn(p.hcp, holes[i].hcp)
            guard let v, v > 0 else { return net ? holes[i].par + 2 : holes[i].par + 2 + st }
            return net ? v - st : v
        }
        let start = teams.first.map { $0.start == 0 ? 1 : $0.start } ?? 1
        // hole indexes this round plays, from the starting hole
        let ph = playHoles(ev).map { $0 - 1 }, k0 = max(0, ph.firstIndex(of: start - 1) ?? 0)
        let order = Array(ph[k0...] + ph[..<k0])
        var ledger = Dictionary(uniqueKeysWithValues: players.map { ($0.key, 0.0) })
        var tally: [String: [String: Double]] = [:]
        var game = ""
        func pay(_ from: String, _ to: String, _ amt: Double) {
            if amt == 0 || from == to { return }
            ledger[from]! -= amt; ledger[to]! += amt
            tally[game, default: [:]][from, default: 0] -= amt; tally[game, default: [:]][to, default: 0] += amt
        }
        var out = SideResult(players: players, ledger: [:])
        let n = players.count

        let sk = cfg.skins
        game = "skins"
        if sk.on && n >= 2 {
            let amt = sk.amt
            var rows: [SideSkinRow] = [], pot = 1
            var won = Dictionary(uniqueKeysWithValues: players.map { ($0.key, 0) })
            for i in order {
                if !players.allSatisfy({ entered($0, i) }) { rows.append(.open(hole: i + 1, pot: pot)); continue }
                let live = players.filter { (raw($0, i) ?? 0) > 0 }
                let best = live.map { val($0, i, sk.net) }.min()
                let who = best.map { b in live.filter { val($0, i, sk.net) == b } } ?? []
                if who.count == 1, let best {
                    rows.append(.won(hole: i + 1, winner: who[0].key, score: best, worth: pot))
                    won[who[0].key]! += pot
                    for p in players { pay(p.key, who[0].key, amt * Double(pot)) }
                    pot = 1
                } else {
                    rows.append(.tied(hole: i + 1, count: who.count, score: best, pot: pot))
                    pot = sk.carry == false ? 1 : pot + 1
                }
            }
            let anyPlayed = rows.contains { if case .open = $0 { return false }; return true }
            out.skins = SideSkins(rows: rows, won: won, carrying: anyPlayed ? pot - 1 : 0)
        }

        let na = cfg.nassau
        game = "nassau"
        if na.on && n >= 2 {
            var A: [SidePlayer] = [], B: [SidePlayer] = []
            for (k, p) in players.enumerated() {
                let s = na.sides[p.key] ?? (teams.count >= 2 ? (p.team == teams[0].id ? "A" : "B") : (k < (n + 1) / 2 ? "A" : "B"))
                if s == "B" { B.append(p) } else { A.append(p) }
            }
            if !A.isEmpty && !B.isEmpty {
                let amt = na.amt
                func seg(_ from: Int, _ to: Int, _ label: String) -> NassauSeg {
                    var a = 0, b = 0, played = 0, all = true
                    for i in from...to {
                        if !(A + B).allSatisfy({ entered($0, i) }) { all = false; continue }
                        played += 1
                        let x = A.map { val($0, i, na.net) }.min()!, y = B.map { val($0, i, na.net) }.min()!
                        if x < y { a += 1 } else if y < x { b += 1 }
                    }
                    let diff = a - b, done = all && played == to - from + 1
                    let winner: String? = done && diff != 0 ? (diff > 0 ? "A" : "B") : nil
                    if let winner {
                        let W = winner == "A" ? A : B, L = winner == "A" ? B : A
                        for l in L { for w in W { pay(l.key, w.key, amt / Double(W.count)) } }
                    }
                    return NassauSeg(label: label, played: played, holes: to - from + 1, diff: diff, done: done, winner: winner)
                }
                out.nassau = SideNassau(sides: ["A": A.map(\.key), "B": B.map(\.key)], segs: ev.format.nine.isEmpty ? [seg(0, 8, "Front 9"), seg(9, 17, "Back 9"), seg(0, 17, "Overall")] : [seg(ph[0], ph[8], "Match")])
            }
        }

        let bi = cfg.birdies
        game = "birdies"
        if bi.on && n >= 2 {
            let amt = bi.amt
            var list: [BirdieHit] = []
            for p in players { for i in order {
                guard let v = raw(p, i), v > 0 else { continue }
                let d = (bi.net ? v - strokesOn(p.hcp, holes[i].hcp) : v) - holes[i].par
                if d > -1 { continue }
                let count = d <= -2 ? 2 : 1
                list.append(BirdieHit(key: p.key, hole: i + 1, count: count, eagle: d <= -2))
                for q in players { pay(q.key, p.key, amt * Double(count)) }
            } }
            out.birdies = list
        }

        func hasScore(_ p: SidePlayer, _ i: Int) -> Bool { (raw(p, i) ?? 0) > 0 }
        func sideOf(_ g: SideConfig.Picks, _ p: SidePlayer, _ k: Int) -> String {
            g.sides[p.key] ?? (teams.count >= 2 ? (p.team == teams[0].id ? "A" : "B") : (k < (n + 1) / 2 ? "A" : "B"))
        }

        // Stableford: points against par on each hole (net double bogey or worse 0, bogey 1, par 2, birdie 3, eagle 4).
        // It is its own table, not part of the points that change hands.
        let sf = cfg.stableford
        if sf.on && n >= 2 {
            out.stableford = players.map { p in
                var pts = 0, thru = 0
                for i in order where entered(p, i) {
                    thru += 1
                    guard let v = raw(p, i), v > 0 else { continue }  // a pick-up scores nothing
                    let s = sf.net ? v - strokesOn(p.hcp, holes[i].hcp) : v
                    pts += max(0, 2 + holes[i].par - s)
                }
                return StablefordRow(key: p.key, points: pts, thru: thru)
            }
        }

        // Vegas: two against two
        let vg = cfg.vegas
        game = "vegas"
        if vg.on && n >= 2 {
            var A: [SidePlayer] = [], B: [SidePlayer] = []
            for (k, p) in players.enumerated() { if sideOf(vg, p, k) == "B" { B.append(p) } else { A.append(p) } }
            if A.count == 2 && B.count == 2 {
                func number(_ s: [SidePlayer], _ i: Int) -> Int {
                    let v = s.map { val($0, i, vg.net) }.sorted()
                    return Int("\(v[0])\(v[1])") ?? 0
                }
                var rows: [VegasHole] = [], total = 0
                for i in order where (A + B).allSatisfy({ entered($0, i) }) {
                    let a = number(A, i), b = number(B, i)
                    rows.append(VegasHole(hole: i + 1, a: a, b: b))
                    total += b - a  // a lower number wins: positive is good for side A
                    let d = Double(abs(b - a)), W = b > a ? A : B, L = b > a ? B : A
                    if b != a { for (w, l) in zip(W, L) { pay(l.key, w.key, d * vg.amt) } }
                }
                out.vegas = SideVegas(sides: ["A": A.map(\.key), "B": B.map(\.key)], holes: rows, total: total)
            } else { out.vegas = SideVegas(sides: ["A": A.map(\.key), "B": B.map(\.key)], holes: [], total: 0); out.vegasNeedsFour = true }
        }

        // Wolf: the wolf rotates in cart order. After the tee shots the wolf takes a partner or goes it alone.
        let wf = cfg.wolf
        game = "wolf"
        if wf.on && n >= 3 {
            var rows: [WolfHole] = []
            for (k, i) in order.enumerated() {
                let wolf = players[k % n]
                let pick = wf.picks["\(i + 1)"]
                let partner = pick.flatMap { pk in pk == "lone" ? "lone" : players.first { $0.key == pk && $0.key != wolf.key }?.key }
                var result: String?
                if let partner, players.allSatisfy({ entered($0, i) }) {
                    let mine = players.filter { $0.key == wolf.key || $0.key == partner }
                    let rest = players.filter { p in !mine.contains { $0.key == p.key } }
                    let x = mine.filter { hasScore($0, i) }.map { val($0, i, wf.net) }.min() ?? Int.max
                    let y = rest.filter { hasScore($0, i) }.map { val($0, i, wf.net) }.min() ?? Int.max
                    let stake = partner == "lone" ? wf.amt * 2 : wf.amt  // going it alone doubles the hole, both ways
                    if x < y { result = "wolf"; for l in rest { for w in mine { pay(l.key, w.key, stake / Double(mine.count)) } } }
                    else if y < x { result = "others"; for l in mine { for w in rest { pay(l.key, w.key, stake / Double(mine.count)) } } }
                    else { result = "tie" }
                }
                rows.append(WolfHole(hole: i + 1, wolf: wolf.key, partner: partner, result: result))
            }
            out.wolf = SideWolf(holes: rows)
        }

        // Closest to the pin on the par 3s, long drive on the par 5s: the cart picks who won, everyone else gives the stake.
        func pickGame(_ g: SideConfig.Picks, _ par: Int, _ name: String) -> [PickHole]? {
            game = name
            guard g.on && n >= 2 else { return nil }
            return order.filter { holes[$0].par == par }.map { i in
                let w = g.picks["\(i + 1)"].flatMap { pk in players.first { $0.key == pk }?.key }
                if let w { for p in players { pay(p.key, w, g.amt) } }
                return PickHole(hole: i + 1, winner: w)
            }
        }
        out.closest = pickGame(cfg.closest, 3, "closest")
        out.longDrive = pickGame(cfg.longDrive, 5, "longDrive")
        out.tally = tally

        // who pays who: the fewest payments that settle everyone up
        func round2(_ x: Double) -> Double { jsRound(x * 100) / 100 }
        struct Bal { var key: String; var v: Double }
        var owe = players.map { Bal(key: $0.key, v: round2(-ledger[$0.key]!)) }.filter { $0.v > 0.004 }.stableSorted { $0.v > $1.v }
        var get = players.map { Bal(key: $0.key, v: round2(ledger[$0.key]!)) }.filter { $0.v > 0.004 }.stableSorted { $0.v > $1.v }
        var i = 0, j = 0
        while i < owe.count && j < get.count {
            let m = round2(min(owe[i].v, get[j].v))
            if m > 0 { out.settle.append(Settle(from: owe[i].key, to: get[j].key, amt: m)) }
            owe[i].v = round2(owe[i].v - m); get[j].v = round2(get[j].v - m)
            if owe[i].v <= 0.004 { i += 1 }
            if get[j].v <= 0.004 { j += 1 }
        }
        out.ledger = ledger
        return out
    }
}
