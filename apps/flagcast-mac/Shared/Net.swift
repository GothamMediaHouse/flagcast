import Foundation

// The flagcast.app JSON calls the Mac apps make, besides the shared ones in the iPhone app's Server.swift
// (tournament state and its WebSocket feed):
//   POST /golf/api/club/<op>        sign in with an emailed code, the club, its people and tournaments (clubs.js)
//   POST /golf/api/new              make a tournament → { id, key }
//   POST /golf/api/<id>/desk        { key, op, … } everything the tournament desk does (golf.js desk() and dayOp())
//   GET  /golf/api/courses?q=       find a course; /golf/api/courses/<id> its scorecard and tees (courses.js)
enum Net {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.httpAdditionalHeaders = ["User-Agent": "FlagcastMac/2.0"]
        return URLSession(configuration: c)
    }()

    static func url(_ path: String) -> URL { URL(string: path, relativeTo: Server.base)!.absoluteURL }

    /// POST a JSON body and return the answer's bytes (throws the server's own { error } message).
    static func post(_ path: String, _ body: [String: Any]) async throws -> Data {
        var req = URLRequest(url: url(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(req)
    }
    static func get(_ path: String) async throws -> Data { try await send(URLRequest(url: url(path))) }

    private static func send(_ req: URLRequest) async throws -> Data {
        let data: Data, r: URLResponse
        do { (data, r) = try await session.data(for: req) }
        catch { throw APIError(status: 0, message: "Can’t reach Flagcast. Check this Mac’s internet connection.") }
        if let h = r as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw APIError(status: h.statusCode, message: msg ?? "The server answered \(h.statusCode).")
        }
        return data
    }
    static func json(_ d: Data) -> [String: Any] { (try? JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:] }
    static func object(_ e: some Encodable) throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(e)) }

    // ---- the desk ----
    static func deskGet(_ id: String, _ key: String) async throws -> DeskEvent {
        try JSONDecoder().decode(DeskEvent.self, from: await post("/golf/api/\(id)/desk", ["key": key, "op": "get"]))
    }
    static func deskSave(_ id: String, _ key: String, _ ev: DeskEvent) async throws -> DeskEvent {
        let setup = try JSONSerialization.jsonObject(with: ev.setupData)
        let d = try await post("/golf/api/\(id)/desk", ["key": key, "op": "save", "setup": setup])
        var saved = try JSONDecoder().decode(DeskEvent.self, from: d)
        saved.stats = ev.stats   // save doesn't send the report counts back
        return saved
    }
    /// A day op (lock, contest, fix, screen, take, flash, nudge, fund, map, scene, replay, groups, stats).
    @discardableResult
    static func desk(_ id: String, _ key: String, _ op: String, _ extra: [String: Any] = [:]) async throws -> [String: Any] {
        var b = extra; b["key"] = key; b["op"] = op
        return json(try await post("/golf/api/\(id)/desk", b))
    }

    // ---- courses ----
    struct FoundCourse: Decodable, Hashable, Identifiable {
        var id: String, name: String, city: String, state: String, at: LatLng?
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            if let n = try? c.decode(Int.self, forKey: .id) { id = String(n) } else { id = c.str(.id) }
            name = c.str(.name); city = c.str(.city); state = c.str(.state); at = try? c.decodeIfPresent(LatLng.self, forKey: .at)
        }
        enum CodingKeys: String, CodingKey { case id, name, city, state, at }
        var place: String { [city, state].filter { !$0.isEmpty }.joined(separator: ", ") }
    }
    struct FoundTee: Decodable, Hashable {
        var name: String, women: Bool, rating: Double?, slope: Double?, par: Int?, yards: Int?, holes: [Hole]
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            name = c.str(.name, "Tees"); women = c.bool(.women, false); rating = c.num(.rating); slope = c.num(.slope)
            par = c.num(.par).map { Int($0) }; yards = c.num(.yards).map { Int($0) }
            struct H: Decodable { var par: Double?, yds: Double?, hcp: Double? }
            let hs = (try? c.decodeIfPresent([H].self, forKey: .holes)) ?? []
            holes = hs.enumerated().map { i, h in Hole(n: i + 1, par: Int(h.par ?? 4), yds: Int(h.yds ?? 0), hcp: Int(h.hcp ?? Double(i + 1))) }
        }
        enum CodingKeys: String, CodingKey { case name, women, rating, slope, par, yards, holes }
        var label: String { name + (women ? " (women)" : "") }
    }
    struct CourseCard: Decodable { var id: String, name: String, city: String, state: String, at: LatLng?, tees: [FoundTee]
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            if let n = try? c.decode(Int.self, forKey: .id) { id = String(n) } else { id = c.str(.id) }
            name = c.str(.name); city = c.str(.city); state = c.str(.state); at = try? c.decodeIfPresent(LatLng.self, forKey: .at); tees = c.list(.tees)
        }
        enum CodingKeys: String, CodingKey { case id, name, city, state, at, tees }
    }
    static func findCourses(_ q: String) async throws -> [FoundCourse] {
        let d = try await get("/golf/api/courses?q=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
        struct R: Decodable { var courses: [Lenient<FoundCourse>] }
        return try JSONDecoder().decode(R.self, from: d).courses.compactMap(\.value)
    }
    static func course(_ id: String) async throws -> CourseCard {
        try JSONDecoder().decode(CourseCard.self, from: await get("/golf/api/courses/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)"))
    }
}

extension DeskEvent {
    /// Fill the course from a scorecard in the course lookup (what Setup → Find the course does on the website):
    /// holes from the tees the field plays, every set of tees with a rating and slope for handicaps, and the course's spot.
    mutating func fill(from card: Net.CourseCard, tee picked: Net.FoundTee) {
        for (i, h) in picked.holes.prefix(18).enumerated() where i < course.holes.count {
            course.holes[i].par = h.par; course.holes[i].yds = h.yds; course.holes[i].hcp = h.hcp
        }
        if let at = card.at { course.at = at }
        if course.name.trimmingCharacters(in: .whitespaces).isEmpty { course.name = card.name }
        let keep = course.tees, par = course.par
        var tees = card.tees.filter { $0.rating != nil && $0.slope != nil }.prefix(8).map { t -> Tee in
            Tee(id: keep.first { $0.name == t.label }?.id ?? Ids.make(), name: t.label, slope: t.slope ?? 113, rating: t.rating ?? 72,
                par: (t.par ?? 0) != par ? (t.par ?? 0) : 0)
        }
        // the tees picked go first, so players without tees set use them
        if let i = tees.firstIndex(where: { $0.name == picked.label }), i > 0 { tees.insert(tees.remove(at: i), at: 0) }
        course.tees = Array(tees)
    }
}
