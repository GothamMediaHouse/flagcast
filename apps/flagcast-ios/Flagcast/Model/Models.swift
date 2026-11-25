import Foundation

// The tournament as the server sends it (GET /golf/api/<id>/state and the WebSocket's { t: 'state', s }).
// golf.js cleanSetup() is the source of truth for these shapes. Decoding is lenient: a missing or odd value
// falls back to the same default the server would use, so one bad field never hides a whole scorecard.

extension KeyedDecodingContainer {
    func num(_ k: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: k) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: k) { return Double(s) }
        return nil
    }
    func int(_ k: Key, _ d: Int) -> Int { num(k).map { Int($0.rounded()) } ?? d }
    func dbl(_ k: Key, _ d: Double) -> Double { num(k) ?? d }
    func str(_ k: Key, _ d: String = "") -> String { (try? decodeIfPresent(String.self, forKey: k)) ?? d }
    func bool(_ k: Key, _ d: Bool) -> Bool { (try? decodeIfPresent(Bool.self, forKey: k)) ?? d }
    func list<T: Decodable>(_ k: Key) -> [T] {
        guard let arr = try? decodeIfPresent([Lenient<T>].self, forKey: k) else { return [] }
        return arr.compactMap(\.value)
    }
}

/// Decodes one array element, or nil when that element is broken (the rest of the array still decodes).
struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

struct Hole: Codable, Hashable {
    var n: Int, par: Int, yds: Int, hcp: Int
    init(n: Int, par: Int, yds: Int = 0, hcp: Int) { self.n = n; self.par = par; self.yds = yds; self.hcp = hcp }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        n = c.int(.n, 1); par = c.int(.par, 4); yds = c.int(.yds, 0); hcp = c.int(.hcp, n)
    }
}

struct Player: Codable, Hashable, Identifiable {
    /// hcp is the playing handicap the scoring uses. When the desk entered a GHIN Handicap Index, the server
    /// has already worked hcp out as the course handicap for the player's tee; index and tee are shown with it.
    var id: String, name: String, hcp: Double, guest: Bool
    var index: Double? = nil, tee: String = ""
    init(id: String, name: String, hcp: Double = 0, guest: Bool = false) { self.id = id; self.name = name; self.hcp = hcp; self.guest = guest }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.str(.id); name = c.str(.name); hcp = c.dbl(.hcp, 0); guest = c.bool(.guest, false)
        index = c.num(.index); tee = c.str(.tee)
    }
}

/// A set of tees with its USGA rating and slope, for course handicaps.
struct Tee: Codable, Hashable, Identifiable {
    var id: String, name: String, slope: Double, rating: Double, par: Int
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.str(.id); name = c.str(.name); slope = c.dbl(.slope, 113); rating = c.dbl(.rating, 72); par = c.int(.par, 0)
    }
}

struct Team: Codable, Hashable, Identifiable {
    var id: String, name: String, flight: String, start: Int, hcp: Double, cart: String, players: [Player]
    init(id: String, name: String = "", flight: String = "", start: Int = 1, hcp: Double = 0, cart: String = "", players: [Player] = []) {
        self.id = id; self.name = name; self.flight = flight; self.start = start; self.hcp = hcp; self.cart = cart; self.players = players
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.str(.id); name = c.str(.name); flight = c.str(.flight); start = c.int(.start, 1); hcp = c.dbl(.hcp, 0)
        cart = c.str(.cart); players = c.list(.players)
    }
    /// The team's name, or its players' names when it has none.
    var displayName: String { name.isEmpty ? players.map(\.name).joined(separator: " / ") : name }
}

struct Format: Codable, Hashable {
    var type: String, count: Int, allowance: Double, show: String
    /// "" = all 18 holes, "front" = holes 1–9, "back" = holes 10–18
    var nine: String = ""
    init(type: String = "bestball", count: Int = 1, allowance: Double = 100, show: String = "net", nine: String = "") {
        self.type = type; self.count = count; self.allowance = allowance; self.show = show; self.nine = nine
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        type = c.str(.type, "bestball"); count = c.int(.count, 1); allowance = c.dbl(.allowance, 100); show = c.str(.show, "net")
        nine = ["front", "back"].contains(c.str(.nine, "")) ? c.str(.nine, "") : ""
    }
    var isScramble: Bool { type == "scramble" }
    var isStableford: Bool { type == "stableford" }
    var name: String { ["bestball": "Best ball", "stroke": "Stroke play", "scramble": "Scramble", "stableford": "Stableford"][type] ?? "Best ball" }
}

struct Course: Codable, Hashable {
    var name: String, holes: [Hole]
    var tees: [Tee] = []
    init(name: String = "", holes: [Hole] = Core.defaultHoles()) { self.name = name; self.holes = holes }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        name = c.str(.name)
        tees = c.list(.tees)
        let h: [Hole] = c.list(.holes)
        holes = h.count == 18 ? h : Core.defaultHoles()
    }
}

struct Screens: Codable, Hashable {
    var title: String = "", ticker: String = "", seconds: Int = 12, skins: Bool = false, rows: Int = 10
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        title = c.str(.title); ticker = c.str(.ticker); seconds = c.int(.seconds, 12); skins = c.bool(.skins, false); rows = c.int(.rows, 10)
    }
}

struct Sponsor: Codable, Hashable, Identifiable {
    var id: String, name: String, line: String, spot: String, holes: [Int], logo: String, url: String, offer: String
    init(id: String, name: String, line: String = "", spot: String = "slide", holes: [Int] = [], logo: String = "", url: String = "", offer: String = "") {
        self.id = id; self.name = name; self.line = line; self.spot = spot; self.holes = holes; self.logo = logo; self.url = url; self.offer = offer
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.str(.id); name = c.str(.name); line = c.str(.line); spot = c.str(.spot, "slide")
        holes = ((try? c.decodeIfPresent([Double].self, forKey: .holes)) ?? []).map { Int($0) }
        logo = c.str(.logo); url = c.str(.url); offer = c.str(.offer)
    }
}

struct ContestEntry: Codable, Hashable { var name: String, dist: Double }
struct Contest: Codable, Hashable, Identifiable {
    var id: String, kind: String, hole: Int, label: String, sponsor: String, entries: [ContestEntry]
    init(id: String, kind: String = "ctp", hole: Int, label: String = "", sponsor: String = "", entries: [ContestEntry] = []) {
        self.id = id; self.kind = kind; self.hole = hole; self.label = label; self.sponsor = sponsor; self.entries = entries
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.str(.id); kind = c.str(.kind, "ctp"); hole = c.int(.hole, 1); label = c.str(.label); sponsor = c.str(.sponsor)
        entries = c.list(.entries)
    }
    var isLongDrive: Bool { kind == "ld" }
    var title: String { label.isEmpty ? (isLongDrive ? "Long drive" : "Closest to the pin") : label }
}

struct PageRef: Codable, Hashable { var k: String; var fl: String = ""; var hole: Int = 0; var sponsor: String = ""; var secs: Int = 12
    /// a page sent to a screen for a while: when it ends (ms since 1970), 0 = until someone changes it
    var until: Double = 0
    init(k: String, fl: String = "", hole: Int = 0, sponsor: String = "", secs: Int = 12) { self.k = k; self.fl = fl; self.hole = hole; self.sponsor = sponsor; self.secs = secs }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        k = c.str(.k); fl = c.str(.fl); hole = c.int(.hole, 0); sponsor = c.str(.sponsor); secs = c.int(.secs, 12); until = c.dbl(.until, 0)
    }
    /// still on: sent until someone changes it, or its time isn't up
    var isOn: Bool { until == 0 || until > Date().timeIntervalSince1970 * 1000 }
}
struct Display: Codable, Hashable, Identifiable {
    var id: String, name: String, playlist: [PageRef]
    /// where it hangs ("Clubhouse bar") and a group to send to together ("Clubhouse")
    var place = "", group = ""
    /// one of the club's TVs (Club TVs): it's in every tournament, and removing it is done there
    var tv = false
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.str(.id); name = c.str(.name); playlist = c.list(.playlist); place = c.str(.place); group = c.str(.group); tv = c.bool(.tv, false)
    }
    enum CodingKeys: String, CodingKey { case id, name, playlist, place = "where", group, tv }
}

struct Fund: Codable, Hashable {
    var on = false, label = "", goal: Double = 0, raised: Double = 0, give = ""
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        on = c.bool(.on, false); label = c.str(.label); goal = c.dbl(.goal, 0); raised = c.dbl(.raised, 0); give = c.str(.give)
    }
}

struct Flash: Codable, Hashable { var text: String; var at: Double }
/// Club branding (brand.js on the server): the club's logo shows instead of the Flagcast logo. `logo` is an address on
/// the server ('' = Flagcast's: no club logo yet, or a tournament Admin marked Demo).
struct Brand: Codable, Hashable {
    var logo = "", accent = "", club = ""
    var demo = true, powered = false
    /// Admin marked the tournament Demo: sample groups walk the course map on any day
    var marked = false
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        logo = c.str(.logo); accent = c.str(.accent); club = c.str(.club); demo = c.bool(.demo, true); powered = c.bool(.powered, false); marked = c.bool(.marked, false)
    }
    /// the club logo's full address, or nil for the Flagcast logo
    var logoURL: URL? { demo || logo.isEmpty ? nil : URL(string: logo, relativeTo: Server.base)?.absoluteURL }
}
/// Photos the club added for golfers (brand.js on the server): a cover photo, one per hole, a wide banner per sponsor.
/// Each is an address on the server; missing ones aren't there.
struct Photos: Codable, Hashable {
    var cover = "", holes: [String: String] = [:], sponsors: [String: String] = [:]
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        cover = c.str(.cover)
        holes = (try? c.decodeIfPresent([String: String].self, forKey: .holes)) ?? [:]
        sponsors = (try? c.decodeIfPresent([String: String].self, forKey: .sponsors)) ?? [:]
    }
    private func url(_ s: String?) -> URL? { guard let s, !s.isEmpty else { return nil }; return URL(string: s, relativeTo: Server.base)?.absoluteURL }
    var coverURL: URL? { url(cover) }
    func hole(_ n: Int) -> URL? { url(holes[String(n)]) }
    func sponsor(_ id: String) -> URL? { url(sponsors[id]) }
}
struct News: Codable, Hashable { var text: String; var at: Double; var by: String? }
/// From the pro shop: to one cart (team), one golfer on it (player), or everyone (team "*").
/// A note to a cart: from the pro shop, or (from) a ready-made note another group sent from the course map.
struct Nudge: Codable, Hashable { var team: String; var player: String? = nil; var text: String; var at: Double; var from: String? = nil }
struct Ace: Codable, Hashable { var hole: Int; var name: String; var team: String; var at: Double }
struct Take: Codable, Hashable { var kind: String; var text: String?; var sponsor: String?; var at: Double; var secs: Double? }
/// "Routed to phones": Admin, the desk or a pro points every player's phone at something (public/golf/phonecast.js).
struct PhoneRoute: Codable, Hashable {
    var k: String, fl: String, hole: Int, sponsor: String, text: String, at: Double
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        k = c.str(.k); fl = c.str(.fl); hole = c.int(.hole, 0); sponsor = c.str(.sponsor); text = c.str(.text); at = c.dbl(.at, 0)
    }
    var isCamera: Bool { k == "cam" || k == "p3" }
}
struct LiveScreens: Codable, Hashable {
    var force: [String: PageRef] = [:], take: Take?, phone: PhoneRoute?
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        force = (try? c.decodeIfPresent([String: PageRef].self, forKey: .force)) ?? [:]
        take = try? c.decodeIfPresent(Take.self, forKey: .take)
        phone = try? c.decodeIfPresent(PhoneRoute.self, forKey: .phone)
    }
}
struct ScheduleItem: Codable, Hashable { var time: String; var what: String }

/// A par 3 replay: a clip link to play from the start, or (url empty) a mark on the hole's live HLS camera,
/// played back from `back` seconds before `at` (ms) using the stream's own clock.
struct Replay: Codable, Hashable, Identifiable {
    var id: String, hole: Int, label: String, url: String, at: Double, back: Double, by: String
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.str(.id); hole = c.int(.hole, 1); label = c.str(.label); url = c.str(.url)
        at = c.dbl(.at, 0); back = c.dbl(.back, 25); by = c.str(.by)
    }
    var isClip: Bool { !url.isEmpty }
}

/// The club's course map for hole GPS (golf.js cleanMap): per hole the tee, the front / middle / back of the green,
/// and hazards (p = where you reach it, c = what carries it). Points are [lat, lng].
struct GeoPoint: Codable, Hashable {
    var lat: Double, lng: Double
    init(lat: Double, lng: Double) { self.lat = lat; self.lng = lng }
    init(from d: Decoder) throws {
        var c = try d.unkeyedContainer()
        lat = try c.decode(Double.self); lng = try c.decode(Double.self)
    }
    func encode(to e: Encoder) throws { var c = e.unkeyedContainer(); try c.encode(lat); try c.encode(lng) }
}
struct Hazard: Codable, Hashable, Identifiable {
    var id: String, k: String, n: String, p: GeoPoint, c: GeoPoint?
}
struct HoleMap: Codable, Hashable {
    var tee: GeoPoint?, f: GeoPoint?, m: GeoPoint?, b: GeoPoint?, hz: [Hazard]
    var line: [GeoPoint] = []   // the bends between the tee and the green (doglegs), in order
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        tee = try? c.decodeIfPresent(GeoPoint.self, forKey: .tee); f = try? c.decodeIfPresent(GeoPoint.self, forKey: .f)
        m = try? c.decodeIfPresent(GeoPoint.self, forKey: .m); b = try? c.decodeIfPresent(GeoPoint.self, forKey: .b)
        hz = c.list(.hz)
        line = (try? c.decodeIfPresent([GeoPoint].self, forKey: .line)) ?? []
    }
}
struct CourseMap: Codable, Hashable {
    var holes: [Int: HoleMap] = [:], src = ""
    enum CodingKeys: String, CodingKey { case holes, src }
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let raw = (try? c.decodeIfPresent([String: Lenient<HoleMap>].self, forKey: .holes)) ?? [:]
        holes = Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in Int(k).flatMap { n in v.value.map { (n, $0) } } })
        src = c.str(.src)
    }
    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(Dictionary(uniqueKeysWithValues: holes.map { (String($0.key), $0.value) }), forKey: .holes)
        try c.encode(src, forKey: .src)
    }
}

/// scores[teamId][playerId or "T"] = 18 values: nil = not yet, 0 = picked up, else strokes
typealias Scores = [String: [String: [Int?]]]


/// Where the pin is on a green today (the Manager's Pin sheet; public/golf/gps.js cleanPin). d: F/M/B (front, middle,
/// back), s: L/C/R (left, center, right), on: paces from the front edge, off: paces in from the left or right edge (0 = not given).
struct PinSpot: Codable, Hashable {
    var d = "M", s = "C", on = 0, off = 0
    init(d: String = "M", s: String = "C", on: Int = 0, off: Int = 0) { self.d = d; self.s = s; self.on = on; self.off = off }
    enum CodingKeys: String, CodingKey { case d, s, on, off }
    init(from dec: Decoder) throws {
        let c = try dec.container(keyedBy: CodingKeys.self)
        d = c.str(.d, "M"); s = c.str(.s, "C"); on = c.int(.on, 0); off = c.int(.off, 0)
    }
    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(d, forKey: .d); try c.encode(s, forKey: .s)
        if on > 0 { try c.encode(on, forKey: .on) }
        if off > 0 && s != "C" { try c.encode(off, forKey: .off) }
    }
    var json: [String: Any] { var o: [String: Any] = ["d": d, "s": s]; if on > 0 { o["on"] = on }; if off > 0 && s != "C" { o["off"] = off }; return o }
    /// "Back right", "Middle", "Front left"
    var label: String {
        let depth = ["F": "Front", "M": "Middle", "B": "Back"][d] ?? "Middle", side = ["L": "left", "R": "right"][s] ?? ""
        return side.isEmpty ? depth : "\(depth) \(side)"
    }
    /// "26 on · 4 R" (as on a printed pin sheet), "" with no paces
    var paces: String { [on > 0 ? "\(on) on" : "", off > 0 && s != "C" ? "\(off) \(s)" : ""].filter { !$0.isEmpty }.joined(separator: " · ") }
    /// Yards to the pin from the yards to the front, middle and back of the green: front + paces on when the paces
    /// are known (a pace is about a yard), else halfway to the middle for a front or back pin.
    func yards(f: Int?, m: Int?, b: Int?) -> Int? {
        if on > 0, let f { return f + on }
        switch d {
        case "F": if let f, let m { return Int((Double(f + m) / 2).rounded()) }; return f ?? m
        case "B": if let b, let m { return Int((Double(m + b) / 2).rounded()) }; return b ?? m
        default: return m ?? f ?? b
        }
    }
    /// Where it sits on the drawn green (a 150 × 140 box, back at the top): x, y
    var spot: (x: Double, y: Double) { (["L": 44, "R": 116][s] ?? 80, ["B": 30, "F": 104][d] ?? 68) }
}

struct EventState: Codable, Hashable {
    var id = "", name = "", club = "", date = ""
    var course = Course()
    var format = Format()
    var sideGames = true
    var flights: [String] = []
    var teams: [Team] = []
    var screens = Screens()
    var cams: [Int: String] = [:]
    var sponsors: [Sponsor] = []
    var schedule: [ScheduleItem] = []
    var displays: [Display] = []
    var fund = Fund()
    var contests: [Contest] = []
    var locked = false
    var aces: [Ace] = []
    var flash: Flash?
    var news: [News] = []
    var nudges: [Nudge] = []
    var live = LiveScreens()
    var replays: [Replay] = []
    var map = CourseMap()
    var pinsheet: [Int: PinSpot] = [:]   // hole → where the pin is today
    var scores: Scores = [:]
    var online: [String: Int] = [:]
    var lastAt: [String: Double] = [:]   // team id → when that cart last entered a score (ms)
    var brand = Brand()
    var photos = Photos()
    /// the desk turned off golfers' ready-made notes to other groups (day op "notes")
    var notesOff = false

    enum CodingKeys: String, CodingKey {
        case id, name, club, date, course, format, sideGames, flights, teams, screens, cams, sponsors, schedule, displays, fund, contests
        case locked, aces, flash, news, nudges, live, replays, map, pinsheet, scores, online, brand, lastAt, photos, notesOff
    }
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.str(.id); name = c.str(.name); club = c.str(.club); date = c.str(.date)
        course = (try? c.decodeIfPresent(Course.self, forKey: .course)) ?? Course()
        format = (try? c.decodeIfPresent(Format.self, forKey: .format)) ?? Format()
        sideGames = c.bool(.sideGames, true)
        flights = (try? c.decodeIfPresent([String].self, forKey: .flights)) ?? []
        teams = c.list(.teams)
        screens = (try? c.decodeIfPresent(Screens.self, forKey: .screens)) ?? Screens()
        let rawCams = (try? c.decodeIfPresent([String: String].self, forKey: .cams)) ?? [:]
        cams = Dictionary(uniqueKeysWithValues: rawCams.compactMap { k, v in Int(k).map { ($0, v) } })
        sponsors = c.list(.sponsors); schedule = c.list(.schedule); displays = c.list(.displays)
        fund = (try? c.decodeIfPresent(Fund.self, forKey: .fund)) ?? Fund()
        contests = c.list(.contests)
        locked = c.bool(.locked, false)
        aces = c.list(.aces)
        flash = try? c.decodeIfPresent(Flash.self, forKey: .flash)
        news = c.list(.news); nudges = c.list(.nudges)
        live = (try? c.decodeIfPresent(LiveScreens.self, forKey: .live)) ?? LiveScreens()
        replays = c.list(.replays)
        map = (try? c.decodeIfPresent(CourseMap.self, forKey: .map)) ?? CourseMap()
        let rawPins = (try? c.decodeIfPresent([String: Lenient<PinSpot>].self, forKey: .pinsheet)) ?? [:]
        pinsheet = Dictionary(uniqueKeysWithValues: rawPins.compactMap { k, v in Int(k).flatMap { n in v.value.map { (n, $0) } } })
        scores = (try? c.decodeIfPresent(Scores.self, forKey: .scores)) ?? [:]
        online = (try? c.decodeIfPresent([String: Int].self, forKey: .online)) ?? [:]
        brand = (try? c.decodeIfPresent(Brand.self, forKey: .brand)) ?? Brand()
        photos = (try? c.decodeIfPresent(Photos.self, forKey: .photos)) ?? Photos()
        lastAt = (try? c.decodeIfPresent([String: Double].self, forKey: .lastAt)) ?? [:]
        notesOff = c.bool(.notesOff, false)
    }
    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(club, forKey: .club); try c.encode(date, forKey: .date)
        try c.encode(course, forKey: .course); try c.encode(format, forKey: .format); try c.encode(sideGames, forKey: .sideGames)
        try c.encode(flights, forKey: .flights); try c.encode(teams, forKey: .teams); try c.encode(screens, forKey: .screens)
        try c.encode(Dictionary(uniqueKeysWithValues: cams.map { (String($0.key), $0.value) }), forKey: .cams)
        try c.encode(sponsors, forKey: .sponsors); try c.encode(schedule, forKey: .schedule); try c.encode(displays, forKey: .displays)
        try c.encode(fund, forKey: .fund); try c.encode(contests, forKey: .contests); try c.encode(locked, forKey: .locked)
        try c.encode(aces, forKey: .aces); try c.encodeIfPresent(flash, forKey: .flash); try c.encode(news, forKey: .news)
        try c.encode(nudges, forKey: .nudges); try c.encode(live, forKey: .live); try c.encode(replays, forKey: .replays); try c.encode(map, forKey: .map); try c.encode(Dictionary(uniqueKeysWithValues: pinsheet.map { (String($0.key), $0.value) }), forKey: .pinsheet); try c.encode(scores, forKey: .scores); try c.encode(online, forKey: .online)
        try c.encode(brand, forKey: .brand); try c.encode(lastAt, forKey: .lastAt); try c.encode(photos, forKey: .photos)
        try c.encode(notesOff, forKey: .notesOff)
    }

    /// "Sat, Nov 21" for the tournament's day (it's stored as 2026-11-21, a day where the club is)
    var dayText: String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        guard let d = f.date(from: date) else { return date }
        return d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
    /// The name shown at the top of pages: the screens title when the desk set one.
    var title: String { screens.title.isEmpty ? (name.isEmpty ? "Tournament" : name) : screens.title }
    func team(_ id: String?) -> Team? { teams.first { $0.id == id } }
    /// Whose scores a team enters: its players, or the whole team as "T" in a scramble.
    func scorers(_ t: Team) -> [Player] { format.isScramble ? [Player(id: "T", name: t.name.isEmpty ? "Team" : t.name, hcp: t.hcp)] : t.players }
    var sideGamesAllowed: Bool { sideGames && !format.isScramble }
}
