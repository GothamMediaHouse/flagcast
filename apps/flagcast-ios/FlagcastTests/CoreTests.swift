import XCTest
@testable import Flagcast

/// The Swift scoring math must give exactly what the website's core.js gives. core-fixture.json holds sample
/// tournaments and core.js's answers for them (regenerate with `node apps/flagcast-ios/tools/make-core-fixture.mjs`).
final class CoreTests: XCTestCase {
    struct Fixture: Decodable {
        struct Case: Decodable { let event: EventState; let scores: Scores }
        let cases: [Case]
    }
    static let url = Bundle(for: CoreTests.self).url(forResource: "core-fixture", withExtension: "json")!
    static let data = try! Data(contentsOf: url)
    static let typed = try! JSONDecoder().decode(Fixture.self, from: data)
    static let raw = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    var rawCases: [[String: Any]] { Self.raw["cases"] as! [[String: Any]] }

    // ---- comparing with the JSON core.js wrote: nulls and missing keys are the same thing ----
    func norm(_ v: Any?) -> Any? {
        // an Optional boxed inside Any (from [String: Any?]) is not `nil` to a switch: open it up first
        if let v, Mirror(reflecting: v).displayStyle == .optional {
            return norm(Mirror(reflecting: v).children.first?.value)
        }
        switch v {
        case nil, is NSNull: return nil
        case let d as [String: Any]: return d.compactMapValues { norm($0) }
        case let a as [Any]: return a.map { norm($0) ?? NSNull() }
        default: return v
        }
    }
    func same(_ a: Any?, _ b: Any?, _ path: String, _ diffs: inout [String]) {
        let a = norm(a), b = norm(b)
        switch (a, b) {
        case (nil, nil): return
        case let (x as [String: Any], y as [String: Any]):
            for k in Set(x.keys).union(y.keys) { same(x[k], y[k], "\(path).\(k)", &diffs) }
        case let (x as [Any], y as [Any]):
            if x.count != y.count { diffs.append("\(path): \(x.count) items vs \(y.count)"); return }
            for i in x.indices { same(x[i], y[i], "\(path)[\(i)]", &diffs) }
        case let (x as String, y as String):
            if x != y { diffs.append("\(path): \(x) vs \(y)") }
        case let (x as NSNumber, y as NSNumber):
            let xb = CFGetTypeID(x) == CFBooleanGetTypeID(), yb = CFGetTypeID(y) == CFBooleanGetTypeID()
            if xb != yb || abs(x.doubleValue - y.doubleValue) > 1e-9 { diffs.append("\(path): \(x) vs \(y)") }
        default:
            diffs.append("\(path): \(String(describing: a)) vs \(String(describing: b))")
        }
    }
    func check(_ swift: Any?, _ js: Any?, _ path: String, file: StaticString = #filePath, line: UInt = #line) {
        var diffs: [String] = []
        same(swift, js, path, &diffs)
        XCTAssert(diffs.isEmpty, "Swift and core.js differ:\n" + diffs.prefix(12).joined(separator: "\n"), file: file, line: line)
    }

    // ---- the Swift results as the same JSON shapes ----
    func j(_ r: CardRow) -> [String: Any?] { ["hole": r.hole, "par": r.par, "gross": r.gross, "net": r.net, "done": r.done, "off": r.off ? true : nil] }
    func j(_ l: Line) -> [String: Any?] {
        ["key": l.key, "teamId": l.teamId, "name": l.name, "sub": l.sub, "flight": l.flight, "start": l.entry.start, "played": l.played,
         "total": l.total, "toPar": l.toPar, "nr": l.nr, "score": l.score, "pos": l.pos, "thru": l.thru, "card": l.card.map(j)]
    }
    func j(_ w: Who) -> [String: Any] { ["name": w.name, "team": w.team] }
    func j(_ s: HoleStats) -> [String: Any?] {
        ["holeNo": s.holeNo, "par": s.par, "eagle": s.eagle, "birdie": s.birdie, "par0": s.par0, "bogey": s.bogey, "worse": s.worse,
         "aces": s.aces.map(j), "n": s.n, "total": s.total, "avg": s.avg]
    }
    func j(_ r: SkinRow) -> [String: Any] {
        switch r {
        case .open(let h): return ["hole": h, "open": true]
        case let .won(h, w, s, worth): return ["hole": h, "won": j(w), "score": s, "worth": worth]
        case let .tied(h, n, s): return ["hole": h, "tied": n, "score": s]
        }
    }
    func j(_ r: SideResult) -> [String: Any?] {
        var o: [String: Any?] = [
            "players": r.players.map { ["key": $0.key, "id": $0.id, "team": $0.team, "name": $0.name, "hcp": $0.hcp, "short": $0.short] },
            "ledger": r.ledger, "settle": r.settle.map { ["from": $0.from, "to": $0.to, "amt": $0.amt] },
        ]
        if let s = r.skins {
            o["skins"] = ["rows": s.rows.map { row -> [String: Any?] in
                switch row {
                case let .open(h, pot): return ["hole": h, "open": true, "pot": pot]
                case let .won(h, w, s, worth): return ["hole": h, "winner": w, "score": s, "worth": worth]
                case let .tied(h, n, s, pot): return ["hole": h, "tied": n, "score": s, "pot": pot]
                }
            }, "won": s.won, "carrying": s.carrying] as [String: Any]
        }
        if let n = r.nassau {
            o["nassau"] = ["sides": n.sides, "segs": n.segs.map { ["label": $0.label, "played": $0.played, "holes": $0.holes, "diff": $0.diff, "done": $0.done, "winner": $0.winner] as [String: Any?] }] as [String: Any]
        }
        if let b = r.birdies { o["birdies"] = ["list": b.map { ["key": $0.key, "hole": $0.hole, "count": $0.count, "eagle": $0.eagle] }] }
        if let s = r.stableford { o["stableford"] = s.map { ["key": $0.key, "points": $0.points, "thru": $0.thru] } }
        if let v = r.vegas { o["vegas"] = ["sides": v.sides, "holes": v.holes.map { ["hole": $0.hole, "a": $0.a, "b": $0.b] }, "total": v.total] as [String: Any] }
        if r.vegasNeedsFour { o["vegasNeedsFour"] = true }
        if let w = r.wolf { o["wolf"] = ["holes": w.holes.map { ["hole": $0.hole, "wolf": $0.wolf, "partner": $0.partner, "result": $0.result] as [String: Any?] }] }
        if let c = r.closest { o["closest"] = c.map { ["hole": $0.hole, "winner": $0.winner] as [String: Any?] } }
        if let l = r.longDrive { o["longDrive"] = l.map { ["hole": $0.hole, "winner": $0.winner] as [String: Any?] } }
        o["tally"] = r.tally
        return o
    }

    func testFixtureHasCases() { XCTAssertEqual(Self.typed.cases.count, rawCases.count); XCTAssertGreaterThan(rawCases.count, 4) }

    func testTeamCards() {
        for (k, c) in Self.typed.cases.enumerated() {
            let js = (rawCases[k]["out"] as! [String: Any])["teamCards"] as! [String: Any]
            for t in c.event.teams { check(Core.teamCard(c.event, t, c.scores[t.id]).map(j), js[t.id], "case\(k).teamCard.\(t.id)") }
        }
    }

    func testLeaderboards() {
        for (k, c) in Self.typed.cases.enumerated() {
            let out = rawCases[k]["out"] as! [String: Any]
            check(Core.leaderboard(c.event, c.scores).map(j), out["leaderboard"], "case\(k).leaderboard")
            check(Core.leaderboard(c.event, c.scores, flight: "A").map(j), out["leaderboardA"], "case\(k).leaderboardA")
            check(Core.leaderboard(c.event, c.scores, mode: "gross").map(j), out["leaderboardGross"], "case\(k).leaderboardGross")
        }
    }

    func testHoleStatsAndSkins() {
        for (k, c) in Self.typed.cases.enumerated() {
            let out = rawCases[k]["out"] as! [String: Any]
            check(c.event.course.holes.map { j(Core.holeStats(c.event, c.scores, $0.n)) }, out["holeStats"], "case\(k).holeStats")
            check(Core.skins(c.event, c.scores).map(j), out["skins"], "case\(k).skins")
            check(Core.skins(c.event, c.scores, carry: false).map(j), out["skinsNoCarry"], "case\(k).skinsNoCarry")
        }
    }

    func testContests() {
        for (k, c) in Self.typed.cases.enumerated() {
            let out = rawCases[k]["out"] as! [String: Any]
            let mine = c.event.contests.map { ct -> [String: Any] in
                let l = Core.contestLeader(ct)
                return ["leader": l.map { ["name": $0.name, "dist": $0.dist] }, "dist": l.map { Core.fmtDist(ct, $0.dist) }]
            }
            check(mine, out["contests"], "case\(k).contests")
        }
    }

    /// Golfers' own entries: TVs leave out waiting ones; the pro's warnings (the same answers as test/contests.test.mjs)
    func testContestChecks() throws {
        let ld = try JSONDecoder().decode(Contest.self, from: Data(#"{"id":"a","kind":"ld","hole":7,"self":true,"check":"all","prize":50,"entries":[{"name":"Al","dist":280,"ok":true},{"name":"Bo","dist":301,"ok":false},{"name":"Cy","dist":250}]}"#.utf8))
        XCTAssertEqual(Core.contestLeader(ld).map(\.name), ["Bo", "Al", "Cy"])
        XCTAssertEqual(Core.contestLeader(ld, checked: true).map(\.name), ["Al", "Cy"])
        XCTAssertEqual(ld.check, "all"); XCTAssertEqual(ld.prize, 50); XCTAssertTrue(ld.golfersEnter)
        XCTAssertEqual(ld.waiting.map(\.name), ["Bo"])
        let enc = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ld)) as! [String: Any]
        XCTAssertEqual(enc["self"] as? Bool, true)
        var g = ContestEntry(name: "Zed", dist: 341); g.by = "golfer"
        var a = ContestEntry(name: "A", dist: 290); a.by = "Pro"
        let field = Contest(id: "b", kind: "ld", hole: 7, entries: [a, ContestEntry(name: "B", dist: 280), g])
        XCTAssertEqual(Core.contestFlag(field, g), "51 yds past everyone else")
        var y = ContestEntry(name: "Y", dist: 300); y.by = "golfer"; y.gps = 255
        XCTAssertEqual(Core.contestFlag(Contest(id: "c", kind: "ld", hole: 7), y), "GPS from the tee said 255 yds")
        var t = ContestEntry(name: "T", dist: 0.3); t.by = "golfer"
        XCTAssertEqual(Core.contestFlag(Contest(id: "d", kind: "ctp", hole: 3), t), "Under 6 inches")
        XCTAssertEqual(Core.contestFlag(field, a), "")
    }

    func testSideGames() {
        var ran = 0
        for (k, c) in Self.typed.cases.enumerated() {
            let list = (rawCases[k]["out"] as! [String: Any])["sideGames"] as! [[String: Any]]
            for (n, sg) in list.enumerated() {
                let ids = sg["teamIds"] as! [String]
                let cfg = try! JSONDecoder().decode(SideConfig.self, from: JSONSerialization.data(withJSONObject: sg["cfg"]!))
                check(j(Core.sideGames(c.event, c.scores, ids, cfg)), sg["out"], "case\(k).sideGames[\(n)]")
                ran += 1
            }
        }
        XCTAssertGreaterThan(ran, 10)
    }

    func testSmallFunctions() {
        for row in Self.raw["strokes"] as! [[Int]] { XCTAssertEqual(Core.strokesOn(row[0], row[1]), row[2], "strokesOn(\(row[0]), \(row[1]))") }
        for row in Self.raw["playing"] as! [[Double]] { XCTAssertEqual(Core.playing(row[0], row[1]), Int(row[2]), "playing(\(row[0]), \(row[1]))") }
        for row in Self.raw["fmtPar"] as! [[Any]] { XCTAssertEqual(Core.fmtPar(row[0] as! Int, row[1] as! Bool), row[2] as! String) }
        for row in Self.raw["marks"] as! [[Any]] { XCTAssertEqual(Core.mark(row[0] as? Int, row[1] as! Int).rawValue, row[2] as! String, "mark(\(row[0]), \(row[1]))") }
        for row in Self.raw["dists"] as! [[Any]] {
            let c = Contest(id: "x", kind: row[0] as! String, hole: 1)
            XCTAssertEqual(Core.fmtDist(c, (row[1] as! NSNumber).doubleValue), row[2] as! String)
        }
    }

    func testStateDecodesLeniently() throws {
        let json = #"{"name":"X","teams":[{"id":"a1b2","players":[{"id":"p1","name":"Ann","hcp":"7"}],"start":3},{"bad":true}],"cams":{"4":"https://x/a.m3u8"},"scores":{"a1b2":{"p1":[4,null,0]}}}"#
        let s = try JSONDecoder().decode(EventState.self, from: Data(json.utf8))
        XCTAssertEqual(s.teams.first?.players.first?.hcp, 7)
        XCTAssertEqual(s.teams.first?.start, 3)
        XCTAssertEqual(s.cams[4], "https://x/a.m3u8")
        XCTAssertEqual(s.course.holes.count, 18)
        XCTAssertEqual(s.scores["a1b2"]?["p1"]?[1], .some(nil))
    }

    // ---- the app-only side games (no core.js answers for these yet, so worked out by hand) ----
    func cart() throws -> EventState {
        let json = #"{"name":"X","teams":[{"id":"ta","players":[{"id":"p1","name":"Ann","hcp":0},{"id":"p2","name":"Bob","hcp":0}],"start":1},{"id":"tb","players":[{"id":"p3","name":"Cy","hcp":0},{"id":"p4","name":"Dee","hcp":0}],"start":1}],"scores":{"ta":{"p1":[4,5,3],"p2":[5,6,4]},"tb":{"p3":[4,4,4],"p4":[6,5,5]}}}"#
        return try JSONDecoder().decode(EventState.self, from: Data(json.utf8))
    }

    func testStablefordVegasWolfAndPicks() throws {
        let ev = try cart()
        var cfg = SideConfig()
        cfg.stableford.on = true; cfg.vegas.on = true; cfg.wolf.on = true; cfg.closest.on = true
        cfg.wolf.picks = ["1": "tb:p3", "2": "lone"]
        cfg.closest.picks = ["4": "tb:p4"]
        let r = Core.sideGames(ev, ev.scores, ["ta", "tb"], cfg)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: r.stableford!.map { ($0.key, $0.points) }), ["ta:p1": 7, "ta:p2": 4, "tb:p3": 7, "tb:p4": 3])
        XCTAssertEqual(r.stableford!.first!.thru, 3)
        XCTAssertFalse(r.vegasNeedsFour)
        XCTAssertEqual(r.vegas!.holes.map { [$0.a, $0.b] }, [[45, 46], [56, 45], [34, 45]])
        XCTAssertEqual(r.vegas!.total, 1)
        XCTAssertEqual(r.tally["vegas"], ["ta:p1": 1, "ta:p2": 1, "tb:p3": -1, "tb:p4": -1])
        XCTAssertEqual(r.wolf!.holes.prefix(3).map(\.result), ["wolf", "others", nil])
        XCTAssertEqual(r.wolf!.holes[2].wolf, "tb:p3")
        XCTAssertEqual(r.tally["wolf"], ["ta:p1": 3, "ta:p2": -7, "tb:p3": 3, "tb:p4": 1])
        XCTAssertEqual(r.closest!.map(\.hole), [4, 7, 11, 16])
        XCTAssertEqual(r.tally["closest"]?["tb:p4"], 6)
        XCTAssertEqual(r.ledger.values.reduce(0, +), 0, accuracy: 1e-9)
        XCTAssertEqual(r.ledger["tb:p4"]!, -1 + 1 + 6, accuracy: 1e-9)
    }

    func testSideGamesNeedEnoughPlayers() throws {
        let ev = try cart()
        var cfg = SideConfig()
        cfg.vegas.on = true; cfg.wolf.on = true; cfg.stableford.on = true; cfg.skins.on = true
        let two = Core.sideGames(ev, ev.scores, ["ta"], cfg)
        XCTAssertTrue(two.vegasNeedsFour)
        XCTAssertNil(two.wolf)
        XCTAssertNotNil(two.stableford)
        let one = Core.sideGames(ev, ["ta": ["p1": [4]]], [], cfg)
        XCTAssertNil(one.skins); XCTAssertNil(one.stableford)
    }

    func testSideConfigKeepsNewGames() throws {
        var cfg = SideConfig()
        cfg.wolf.on = true; cfg.wolf.picks = ["3": "lone"]; cfg.longDrive.amt = 4
        let back = try JSONDecoder().decode(SideConfig.self, from: JSONEncoder().encode(cfg))
        XCTAssertEqual(back, cfg)
        // an old saved config (before these games) still opens, with them off
        let old = try JSONDecoder().decode(SideConfig.self, from: Data(#"{"skins":{"on":true,"amt":5}}"#.utf8))
        XCTAssertTrue(old.skins.on); XCTAssertFalse(old.wolf.on); XCTAssertEqual(old.closest.amt, 2)
    }
}
