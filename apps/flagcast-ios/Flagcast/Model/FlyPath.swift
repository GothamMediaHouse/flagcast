import Foundation

/// The path "Fly the hole" follows: the hole as it's played, not a straight line from tee to green.
/// Its bends come from the course map's line (OpenStreetMap's hole line, kept when the course was mapped); a hole
/// without one uses its lay-up spots, and failing that flies straight. Kept free of MapKit so tests can check it.
struct FlyPath: Equatable {
    struct Stop: Equatable { var at: GeoPoint; var heading: Double; var secs: Double }
    var points: [GeoPoint]     // tee, bends, green
    var stops: [Stop]          // where the camera looks, which way it faces, and how long it takes to get there
    var back: Double = 0       // yards from the camera to where it looks, along the ground
    var flySecs: Double { stops.dropFirst().reduce(0) { $0 + $1.secs } }
    /// MapKit's camera distance (metres, along the 60° line of sight) that puts the camera `back` yards behind
    var cameraMetres: Double { back / Geo.YD / sin(60 * .pi / 180) }

    /// tee → the bends (in order down the hole, only ones between the tee and the green) → green
    static func holePath(_ h: HoleMap, tee: GeoPoint, green g: GeoPoint) -> [GeoPoint] {
        var bends = h.line
        if bends.isEmpty { bends = h.hz.filter { $0.k == "layup" }.map(\.p) }
        let total = Geo.yds(tee, g) ?? 0
        bends = bends.filter { b in
            let a = Geo.yds(tee, b) ?? 0, c = Geo.yds(b, g) ?? 0
            return a > 25 && c > 25 && a < total + 60
        }
        .sorted { (Geo.yds(tee, $0) ?? 0) < (Geo.yds(tee, $1) ?? 0) }
        return [tee] + bends + [g]
    }

    /// The point `s` yards along a path from its start (the end if past it).
    static func point(_ pts: [GeoPoint], at s: Double) -> GeoPoint {
        var left = max(0, s)
        for (a, b) in zip(pts, pts.dropFirst()) {
            let len = Geo.yds(a, b) ?? 0
            if left <= len, len > 0 { return Geo.offset(a, yards: left, bearing: Geo.bearing(a, b)) }
            left -= len
        }
        return pts.last!
    }
    static func length(_ pts: [GeoPoint]) -> Double { zip(pts, pts.dropFirst()).reduce(0) { $0 + (Geo.yds($1.0, $1.1) ?? 0) } }

    /// The camera looks at a point that travels down the hole (never past the green), facing the way the hole runs
    /// there, and sits `back` yards behind it. `look` is how far behind it sits on a long hole; on a short one it
    /// comes in closer, so it starts just behind the tee and the whole flight stays over the hole.
    static func make(_ h: HoleMap, tee: GeoPoint, green g: GeoPoint, look: Double, seconds: Double = 6) -> FlyPath {
        let pts = holePath(h, tee: tee, green: g), total = max(40, length(pts))
        let back = min(look, total * 0.45 + 30)              // camera to look point, along the ground
        let s0 = max(10, back - 30), s1 = max(s0 + 10, total - 25)
        let dir: (Double) -> Double = { s in Geo.bearing(point(pts, at: max(0, s - 35)), point(pts, at: min(total, s + 35))) }
        let n = max(3, Int(((s1 - s0) / 35).rounded(.up)))
        var stops: [Stop] = []
        for i in 0...n {
            let s = s0 + (s1 - s0) * Double(i) / Double(n)
            stops.append(Stop(at: point(pts, at: s), heading: dir(s), secs: i == 0 ? 0 : seconds / Double(n)))
        }
        // headings without the 359° → 1° jump, so the camera turns the short way
        for i in 1..<stops.count {
            var h = stops[i].heading
            while h - stops[i - 1].heading > 180 { h -= 360 }
            while h - stops[i - 1].heading < -180 { h += 360 }
            stops[i].heading = h
        }
        return FlyPath(points: pts, stops: stops, back: back)
    }
    /// a heading in the same turn as the last stop
    func unwrap(_ h0: Double) -> Double {
        var h = h0
        let last = stops.last?.heading ?? 0
        while h - last > 180 { h -= 360 }
        while h - last < -180 { h += 360 }
        return h
    }
}
