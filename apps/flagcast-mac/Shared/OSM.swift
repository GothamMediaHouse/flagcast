import Foundation

/// Course maps made automatically from OpenStreetMap (a port of public/golf/osm.js). Many courses there have each
/// hole drawn as a line from tee to green (golf=hole, ref = hole number), with greens, bunkers and water as shapes.
/// This turns that into Flagcast's map: tee, front / middle / back of the green, and hazards (reach and carry).
/// Map data © OpenStreetMap contributors (ODbL).
enum OSM {
    static let credit = "Course data © OpenStreetMap contributors"
    struct Element: Decodable { var tags: [String: String]?; var geometry: [G]?
        struct G: Decodable { var lat: Double, lon: Double }
    }
    struct Result { var holes: [Int: HoleMap]; var found: [Int]; var unnumbered: Int }

    /// Golf shapes in a box (south, west, north, east).
    static func fetch(south: Double, west: Double, north: Double, east: Double) async throws -> [Element] {
        let bb = "\(south),\(west),\(north),\(east)"
        let q = "[out:json][timeout:25];(way[\"golf\"=\"hole\"](\(bb));way[\"golf\"~\"^(green|tee|bunker|water_hazard|lateral_water_hazard|fairway)$\"](\(bb));way[\"natural\"=\"water\"](\(bb));way[\"natural\"=\"sand\"](\(bb)););out geom;"
        struct R: Decodable { var elements: [Element]? }
        var last: Error = APIError(status: 0, message: "The map data service didn’t answer. Try again.")
        // the main server, then a public mirror when it's busy (it often is at peak times)
        for server in ["https://overpass-api.de/api/interpreter", "https://overpass.private.coffee/api/interpreter"] {
            var req = URLRequest(url: URL(string: server)!)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.setValue("FlagcastMac/2.0 (golf course maps; https://flagcast.app)", forHTTPHeaderField: "User-Agent")   // the service refuses requests without one
            req.httpBody = ("data=" + (q.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")).data(using: .utf8)
            req.timeoutInterval = 40
            do {
                let (d, r) = try await URLSession.shared.data(for: req)
                if let h = r as? HTTPURLResponse, h.statusCode != 200 {
                    last = APIError(status: h.statusCode, message: [429, 502, 503, 504].contains(h.statusCode) ? "The map data service is busy. Try again in a minute." : "The map data service didn’t answer. Try again.")
                    continue
                }
                if let els = try? JSONDecoder().decode(R.self, from: d).elements { return els }
            } catch { last = error }
        }
        throw last
    }

    typealias XY = (x: Double, y: Double)
    struct Shape { var k: String; var name: String; var xy: [XY]; var c: XY }
    private static func d(_ a: XY, _ b: XY) -> Double { hypot(a.x - b.x, a.y - b.y) }
    private static func centroid(_ p: [XY]) -> XY {
        let n = p.count - (p.count > 1 && d(p[0], p[p.count - 1]) < 0.5 ? 1 : 0)
        guard n > 0 else { return (0, 0) }
        var x = 0.0, y = 0.0; for i in 0..<n { x += p[i].x; y += p[i].y }
        return (x / Double(n), y / Double(n))
    }
    private static func toSeg(_ p: XY, _ a: XY, _ b: XY) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y, L2 = max(dx * dx + dy * dy, 1e-9)
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / L2))
        return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }
    private static func toPath(_ p: XY, _ line: [XY]) -> Double { (1..<max(line.count, 1)).map { toSeg(p, line[$0 - 1], line[$0]) }.min() ?? .infinity }

    /// The map from the shapes; `near` (lat, lng) picks between holes with the same number (27-hole clubs).
    static func build(_ els: [Element], near: GeoPoint?) -> Result {
        let holesEl = els.filter { $0.tags?["golf"] == "hole" && ($0.geometry?.count ?? 0) >= 2 }
        var o = GeoPoint(lat: 0, lng: 0)
        if let near { o = near }
        else if let g = (holesEl.first ?? els.first)?.geometry?.first { o = GeoPoint(lat: g.lat, lng: g.lon) }
        let kx = 111320 * cos(o.lat * .pi / 180), ky = 110574.0
        func to(_ g: Element.G) -> XY { ((g.lon - o.lng) * kx, (g.lat - o.lat) * ky) }
        func back(_ q: XY) -> GeoPoint { GeoPoint(lat: o.lat + q.y / ky, lng: o.lng + q.x / kx) }
        func xy(_ e: Element) -> [XY] { (e.geometry ?? []).map(to) }

        var greens: [Shape] = [], hazards: [Shape] = []
        for e in els {
            guard let t = e.tags, e.geometry != nil else { continue }
            let p = xy(e); if p.isEmpty { continue }
            if t["golf"] == "green" { greens.append(Shape(k: "green", name: "", xy: p, c: centroid(p))); continue }
            let bunker = t["golf"] == "bunker" || t["natural"] == "sand"
            let water = t["golf"] == "water_hazard" || t["golf"] == "lateral_water_hazard" || t["natural"] == "water"
            if bunker || water { hazards.append(Shape(k: bunker ? "bunker" : "water", name: t["name"] ?? "", xy: p, c: centroid(p))) }
        }
        var byRef: [Int: (line: [XY], d: Double)] = [:], unnumbered = 0
        for h in holesEl {
            guard let n = Int(h.tags?["ref"] ?? ""), (1...18).contains(n) else { unnumbered += 1; continue }
            let line = xy(h), dd = hypot(line[0].x, line[0].y)
            if byRef[n] == nil || dd < byRef[n]!.d { byRef[n] = (line, dd) }
        }
        var out: [Int: HoleMap] = [:]
        for (n, v) in byRef {
            let line = v.line, tee = line[0], end = line[line.count - 1], prev = line[line.count - 2]
            var dir: XY = (end.x - prev.x, end.y - prev.y); let dl = max(hypot(dir.x, dir.y), 1e-9); dir = (dir.x / dl, dir.y / dl)
            var f: XY, m: XY, b: XY
            let near = greens.min { d($0.c, end) < d($1.c, end) }
            if let g = near, d(g.c, end) < 45 {
                m = g.c
                let proj = g.xy.map { ($0.x - m.x) * dir.x + ($0.y - m.y) * dir.y }
                let lo = proj.min() ?? -12, hi = proj.max() ?? 12
                f = (m.x + dir.x * lo, m.y + dir.y * lo); b = (m.x + dir.x * hi, m.y + dir.y * hi)
            } else { m = end; f = (end.x - dir.x * 12, end.y - dir.y * 12); b = (end.x + dir.x * 12, end.y + dir.y * 12) }
            let path = Array(line.dropLast()) + [m]
            var hz: [(Hazard, Double)] = []
            for z in hazards {
                if toPath(centroid(z.xy), path) > 35 && (z.xy.map { toPath($0, path) }.min() ?? .infinity) > 12 { continue }
                let along = z.xy.map { ($0, d($0, tee)) }
                guard let near = along.min(by: { $0.1 < $1.1 }), let far = along.max(by: { $0.1 < $1.1 }) else { continue }
                if near.1 < 30 || near.1 > d(tee, b) + 15 { continue }
                let c = centroid(z.xy), side = (c.x - tee.x) * (m.y - tee.y) - (c.y - tee.y) * (m.x - tee.x)
                let greenside = d(c, m) < 45
                let label = z.name.isEmpty ? "\(greenside ? "Greenside" : side > 0 ? "Right" : "Left") \(z.k == "bunker" ? "bunker" : "water")" : z.name
                hz.append((Hazard(id: Ids.make(), k: z.k, n: String(label.prefix(40)), p: back(near.0), c: greenside && z.k == "bunker" ? nil : back(far.0)), near.1))
            }
            hz.sort { $0.1 < $1.1 }
            out[n] = HoleMap(tee: back(tee), f: back(f), m: back(m), b: back(b), hz: Array(hz.prefix(10).map(\.0)))
        }
        return Result(holes: out, found: out.keys.sorted(), unnumbered: unnumbered)
    }
}
