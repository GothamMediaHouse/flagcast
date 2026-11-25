import Foundation

// A tournament as the desk sees it: POST /golf/api/<id>/desk { key, op: "get" }. Saving sends the whole setup back
// ({ op: "save", setup }), and golf.js cleanSetup() rebuilds it from exactly these fields. So every field cleanSetup
// reads is here, including the desk-only ones the public state leaves out (cart codes, GHIN numbers, PINs, the
// course's location). Holes, formats, sponsors, contests, screens and the course map reuse the iPhone app's types.

struct LatLng: Codable, Hashable { var lat: Double, lng: Double }

struct DeskPlayer: Codable, Hashable, Identifiable {
    var id: String, name: String, hcp: Double, guest: Bool
    var ghin: String = "", index: Double? = nil, tee: String = ""
    enum CodingKeys: String, CodingKey { case id, name, hcp, guest, ghin, index, tee }
    init(id: String = Ids.make(), name: String = "", hcp: Double = 0, guest: Bool = false) { self.id = id; self.name = name; self.hcp = hcp; self.guest = guest }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.str(.id); name = c.str(.name); hcp = c.dbl(.hcp, 0); guest = c.bool(.guest, false)
        ghin = c.str(.ghin); index = c.num(.index); tee = c.str(.tee)
    }
    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(hcp, forKey: .hcp); try c.encode(guest, forKey: .guest)
        try c.encode(ghin, forKey: .ghin); try c.encode(index, forKey: .index); try c.encode(tee, forKey: .tee)
    }
}

struct DeskTeam: Codable, Hashable, Identifiable {
    var id: String, code: String = "", name: String, flight: String, start: Int, hcp: Double, cart: String, players: [DeskPlayer]
    /// match play team cup: "A", "B" or ""
    var side: String = ""
    init(id: String = Ids.make(6), name: String = "", flight: String = "", start: Int = 1, players: [DeskPlayer] = []) {
        self.id = id; self.name = name; self.flight = flight; self.start = start; self.hcp = 0; self.cart = ""; self.players = players
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.str(.id); code = c.str(.code); name = c.str(.name); flight = c.str(.flight); start = c.int(.start, 1); hcp = c.dbl(.hcp, 0)
        cart = c.str(.cart); players = c.list(.players); side = c.str(.side)
    }
    /// "Fox / Lee": the name, or the players' last names
    var shortName: String { name.isEmpty ? players.map { $0.name.split(separator: " ").last.map(String.init) ?? $0.name }.filter { !$0.isEmpty }.joined(separator: " / ") : name }
    var displayName: String { name.isEmpty ? players.map(\.name).filter { !$0.isEmpty }.joined(separator: " / ") : name }
}

struct DeskCourse: Codable, Hashable {
    var name: String = "", holes: [Hole] = Core.defaultHoles(), tees: [Tee] = [], at: LatLng? = nil
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        name = c.str(.name); tees = c.list(.tees)
        let h: [Hole] = c.list(.holes)
        holes = h.count == 18 ? h : Core.defaultHoles()
        at = try? c.decodeIfPresent(LatLng.self, forKey: .at)
    }
    var par: Int { holes.reduce(0) { $0 + $1.par } }
}

/// A golf pro or marshal: they sign in to the phone app with the tournament code and this PIN.
struct StaffPin: Codable, Hashable, Identifiable {
    var id: String, name: String, role: String, pin: String
    init(id: String = Ids.make(), name: String = "", role: String = "pro", pin: String = "") { self.id = id; self.name = name; self.role = role; self.pin = pin }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.str(.id); name = c.str(.name); role = c.str(.role, "pro"); pin = c.str(.pin)
    }
    /// A new 6-digit PIN no one else in the tournament has (golf.js pinProblem refuses shorter new ones and repeats).
    static func newPin(_ taken: [StaffPin]) -> String {
        var p: String
        repeat { p = String(Int.random(in: 100000...999999)) } while taken.contains { $0.pin == p }
        return p
    }
}

/// A saved routing of the screens (what each one shows), put back with one click.
struct ScreenScene: Codable, Hashable, Identifiable {
    var id: String, name: String
    init(from d: Decoder) throws { let c = try d.container(keyedBy: CodingKeys.self); id = c.str(.id); name = c.str(.name) }
}

/// Sponsor counts for the report: views and taps on phones, seconds on the screens.
struct SponsorStat: Codable, Hashable { var view: Double = 0, tap: Double = 0, secs: Double = 0
    init(from d: Decoder) throws { let c = try d.container(keyedBy: CodingKeys.self); view = c.dbl(.view, 0); tap = c.dbl(.tap, 0); secs = c.dbl(.secs, 0) }
}
/// A score a pro or the desk changed on the day.
struct FixLog: Codable, Hashable { var at: Double, by: String, team: String, player: String, h: Int, from: Int?, to: Int?
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        at = c.dbl(.at, 0); by = c.str(.by); team = c.str(.team); player = c.str(.player); h = c.int(.h, 0)
        from = c.num(.from).map { Int($0) }; to = c.num(.to).map { Int($0) }
    }
}

struct DeskEvent: Codable, Hashable {
    // the setup (what Save sends)
    var name = "", club = "", date = ""
    var course = DeskCourse()
    var format = Format()
    var sideGames = true
    var flights: [String] = []
    var teams: [DeskTeam] = []
    /// match play pairings (team a v team b)
    var matches: [MatchPair] = []
    var screens = Screens()
    var cams: [Int: String] = [:]
    var sponsors: [Sponsor] = []
    var schedule: [ScheduleItem] = []
    var pins: [StaffPin] = []
    var displays: [Display] = []
    var fund = Fund()
    var contests: [Contest] = []
    var logo = ""   // this tournament's own logo (a PNG data: URI) instead of its club's; '' = the club's
    // the rest: read only here, changed with their own ops
    var id = "", key = ""
    /// the setup version this copy was loaded at: Save sends it, so the server keeps what changed since (golf.js mergeTeams)
    var v = 0
    var locked = false
    var aces: [Ace] = []
    var map = CourseMap()
    var live = LiveScreens()
    var scenes: [ScreenScene] = []
    var replays: [Replay] = []
    var news: [News] = []
    var stats: [String: SponsorStat] = [:]
    var log: [FixLog] = []
    var photos = Photos()   // the photos golfers see (op "photo", saved at once, never with Save)

    enum CodingKeys: String, CodingKey {
        case name, club, date, course, format, sideGames, flights, teams, matches, screens, cams, sponsors, schedule, pins, displays, fund, contests, logo
        case id, key, locked, aces, map, live, scenes, replays, news, stats, log, photos, v
    }
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        name = c.str(.name); club = c.str(.club); date = c.str(.date)
        course = (try? c.decodeIfPresent(DeskCourse.self, forKey: .course)) ?? DeskCourse()
        format = (try? c.decodeIfPresent(Format.self, forKey: .format)) ?? Format()
        sideGames = c.bool(.sideGames, true)
        flights = (try? c.decodeIfPresent([String].self, forKey: .flights)) ?? []
        teams = c.list(.teams); matches = c.list(.matches)
        screens = (try? c.decodeIfPresent(Screens.self, forKey: .screens)) ?? Screens()
        let rawCams = (try? c.decodeIfPresent([String: String].self, forKey: .cams)) ?? [:]
        cams = Dictionary(uniqueKeysWithValues: rawCams.compactMap { k, v in Int(k).map { ($0, v) } })
        sponsors = c.list(.sponsors); schedule = c.list(.schedule); pins = c.list(.pins); displays = c.list(.displays)
        fund = (try? c.decodeIfPresent(Fund.self, forKey: .fund)) ?? Fund()
        contests = c.list(.contests); logo = c.str(.logo)
        id = c.str(.id); key = c.str(.key); locked = c.bool(.locked, false); aces = c.list(.aces); v = Int(c.dbl(.v, 0))
        map = (try? c.decodeIfPresent(CourseMap.self, forKey: .map)) ?? CourseMap()
        live = (try? c.decodeIfPresent(LiveScreens.self, forKey: .live)) ?? LiveScreens()
        scenes = c.list(.scenes); replays = c.list(.replays); news = c.list(.news)
        stats = (try? c.decodeIfPresent([String: Lenient<SponsorStat>].self, forKey: .stats))?.compactMapValues(\.value) ?? [:]
        log = c.list(.log)
        photos = (try? c.decodeIfPresent(Photos.self, forKey: .photos)) ?? Photos()
    }
    /// Only the setup goes back on Save; cleanSetup ignores anything else.
    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name); try c.encode(club, forKey: .club); try c.encode(date, forKey: .date)
        try c.encode(course, forKey: .course); try c.encode(format, forKey: .format); try c.encode(sideGames, forKey: .sideGames)
        try c.encode(flights, forKey: .flights); try c.encode(teams, forKey: .teams); try c.encode(matches, forKey: .matches); try c.encode(screens, forKey: .screens)
        try c.encode(Dictionary(uniqueKeysWithValues: cams.map { (String($0.key), $0.value) }), forKey: .cams)
        try c.encode(sponsors, forKey: .sponsors); try c.encode(schedule, forKey: .schedule); try c.encode(pins, forKey: .pins)
        try c.encode(displays, forKey: .displays); try c.encode(fund, forKey: .fund); try c.encode(contests, forKey: .contests)
        try c.encode(logo, forKey: .logo); try c.encode(v, forKey: .v)
    }
    /// The setup as JSON, for comparing (unsaved changes) and for Save.
    var setupData: Data { (try? Self.encoder.encode(self)) ?? Data() }
    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return e }()

    /// Match play: pair the teams up, 1 v 2, 3 v 4… (shuffled first for a draw). With a team cup, each match is a
    /// team from one side against a team from the other.
    mutating func pairUp(random: Bool) {
        var list = teams
        if random { list.shuffle() }
        var out: [MatchPair] = []
        if format.cup.on && list.contains(where: { !$0.side.isEmpty }) {
            let a = list.filter { $0.side != "B" }, b = list.filter { $0.side == "B" }
            for i in 0..<min(a.count, b.count) { out.append(MatchPair(a: a[i].id, b: b[i].id)) }
        } else {
            var i = 0
            while i + 1 < list.count { out.append(MatchPair(a: list[i].id, b: list[i + 1].id)); i += 2 }
        }
        matches = out
    }
    /// teams not in any match yet
    var unpaired: [DeskTeam] { let used = Set(matches.flatMap { [$0.a, $0.b] }); return teams.filter { !used.contains($0.id) } }

    /// Holes this round plays (front or back 9, or all 18).
    var playHoles: [Int] { switch format.nine { case "front": return Array(1...9); case "back": return Array(10...18); default: return Array(1...18) } }
}

// MARK: - handicaps (public/golf/core.js courseHcp, parseIndex)

enum Hcp {
    /// Course handicap from a Handicap Index: Index × Slope ÷ 113 + (Rating − Par).
    static func course(_ index: Double?, _ tee: Tee?, par: Int) -> Int? {
        guard let index, let tee, tee.slope > 0, tee.rating > 0 else { return nil }
        return Int(jsRound(index * tee.slope / 113 + (tee.rating - Double(tee.par > 0 ? tee.par : par))))
    }
    /// "+1.2" is a plus handicap: stored as -1.2.
    static func parseIndex(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces); if t.isEmpty { return nil }
        guard let n = Double(t.hasPrefix("+") ? String(t.dropFirst()) : t) else { return nil }
        return t.hasPrefix("+") ? -n : n
    }
}

/// Ids like the server makes: lowercase letters and digits without look-alikes.
enum Ids {
    static func make(_ n: Int = 5) -> String { String((0..<n).map { _ in Array("abcdefghijkmnpqrstuvwxyz23456789").randomElement()! }) }
}

// Memberwise inits for iPhone-app types that only have decoders.
extension Tee {
    init(id: String = Ids.make(), name: String, slope: Double, rating: Double, par: Int = 0) { self.id = id; self.name = name; self.slope = slope; self.rating = rating; self.par = par }
}
extension Display {
    init(id: String = Ids.make(), name: String, playlist: [PageRef] = [], place: String = "", group: String = "") { self.id = id; self.name = name; self.playlist = playlist; self.place = place; self.group = group }
}
extension HoleMap {
    init(tee: GeoPoint? = nil, f: GeoPoint? = nil, m: GeoPoint? = nil, b: GeoPoint? = nil, hz: [Hazard] = [], line: [GeoPoint] = []) { self.tee = tee; self.f = f; self.m = m; self.b = b; self.hz = hz; self.line = line }
}
extension ScheduleItem { init() { self.init(time: "", what: "") } }
