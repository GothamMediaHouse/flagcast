import Foundation

/// The path "Fly the hole" follows: the hole as it's played, not a straight line from tee to green.
/// Its bends come from the course map's line (OpenStreetMap's hole line, kept when the course was mapped); a hole
/// without one uses its lay-up spots, and failing that flies straight. Kept free of MapKit so tests can check it.
struct FlyPath: Equatable {
    struct Stop: Equatable { var at: GeoPoint; var heading: Double; var secs: Double }
    var points: [GeoPoint]     // tee, bends, green
    var stops: [Stop]          // where the camera looks, which way it faces, and how long it takes to get there
    var back: Double = 0       // yards from the camera to where it looks, along the ground
    /// The opening shot: low on the tee box, nearly level, looking down the hole the way the golfer sees it; then the
    /// flight climbs away down the fairway.
    var start: Stop = Stop(at: GeoPoint(lat: 0, lng: 0), heading: 0, secs: 0)
    static let startPitch = 78.0, startLook = 70.0      // degrees from straight down; yards from the tee to where it looks
    /// camera distance for the opening shot: about 10 yds behind the tee, some 25 m up
    static var startMetres: Double { (startLook + 10) / YD / sin(startPitch * .pi / 180) }
    var flySecs: Double { stops.dropFirst().reduce(0) { $0 + $1.secs } }
    /// MapKit's camera distance (metres, along the 60° line of sight) that puts the camera `back` yards behind
    var cameraMetres: Double { back / FlyPath.YD / sin(60 * .pi / 180) }

        // distances on the course (the same sums as Geo, kept here so the Mac Manager can share this file)
    static let YD = 1.0936133, R = 6371008.8
    static func yds(_ a: GeoPoint?, _ b: GeoPoint?) -> Double? {
        guard let a, let b else { return nil }
        let t = Double.pi / 180, dla = (b.lat - a.lat) * t, dlo = (b.lng - a.lng) * t
        let h = pow(sin(dla / 2), 2) + cos(a.lat * t) * cos(b.lat * t) * pow(sin(dlo / 2), 2)
        return 2 * R * asin(min(1, sqrt(h))) * YD
    }
    static func bearing(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let t = Double.pi / 180, la1 = a.lat * t, la2 = b.lat * t, dlo = (b.lng - a.lng) * t
        return (atan2(sin(dlo) * cos(la2), cos(la1) * sin(la2) - sin(la1) * cos(la2) * cos(dlo)) / t + 360).truncatingRemainder(dividingBy: 360)
    }
    static func offset(_ a: GeoPoint, yards: Double, bearing deg: Double) -> GeoPoint {
        let t = Double.pi / 180, d = yards / YD / R, br = deg * t, la1 = a.lat * t, lo1 = a.lng * t
        let la2 = asin(sin(la1) * cos(d) + cos(la1) * sin(d) * cos(br))
        let lo2 = lo1 + atan2(sin(br) * sin(d) * cos(la1), cos(d) - sin(la1) * sin(la2))
        return GeoPoint(lat: la2 / t, lng: lo2 / t)
    }

    /// tee → the bends (in order down the hole, only ones between the tee and the green) → green
    static func holePath(_ h: HoleMap, tee: GeoPoint, green g: GeoPoint) -> [GeoPoint] {
        var bends = h.line
        if bends.isEmpty { bends = h.hz.filter { $0.k == "layup" }.map(\.p) }
        let total = FlyPath.yds(tee, g) ?? 0
        bends = bends.filter { b in
            let a = FlyPath.yds(tee, b) ?? 0, c = FlyPath.yds(b, g) ?? 0
            return a > 25 && c > 25 && a < total + 60
        }
        .sorted { (FlyPath.yds(tee, $0) ?? 0) < (FlyPath.yds(tee, $1) ?? 0) }
        return [tee] + bends + [g]
    }

    /// The point `s` yards along a path from its start (the end if past it).
    static func point(_ pts: [GeoPoint], at s: Double) -> GeoPoint {
        var left = max(0, s)
        for (a, b) in zip(pts, pts.dropFirst()) {
            let len = FlyPath.yds(a, b) ?? 0
            if left <= len, len > 0 { return FlyPath.offset(a, yards: left, bearing: FlyPath.bearing(a, b)) }
            left -= len
        }
        return pts.last!
    }
    static func length(_ pts: [GeoPoint]) -> Double { zip(pts, pts.dropFirst()).reduce(0) { $0 + (FlyPath.yds($1.0, $1.1) ?? 0) } }

    /// The camera looks at a point that travels down the hole (never past the green), facing the way the hole runs
    /// there, and sits `back` yards behind it. `look` is how far behind it sits on a long hole; on a short one it
    /// comes in closer, so it starts just behind the tee and the whole flight stays over the hole.
    static func make(_ h: HoleMap, tee: GeoPoint, green g: GeoPoint, look: Double, seconds: Double = 6) -> FlyPath {
        let pts = holePath(h, tee: tee, green: g), total = max(40, length(pts))
        let back = min(look, total * 0.45 + 30)              // camera to look point, along the ground
        let s0 = max(10, back - 30), s1 = max(s0 + 10, total - 25)
        let dir: (Double) -> Double = { s in FlyPath.bearing(point(pts, at: max(0, s - 35)), point(pts, at: min(total, s + 35))) }
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
        let s0look = min(startLook, total * 0.6)
        var p = FlyPath(points: pts, stops: stops, back: back)
        p.s0 = s0; p.s1 = s1; p.totalYds = total; p.travelSecs = seconds
        p.start = Stop(at: point(pts, at: s0look), heading: p.smoothHeading(at: min(s0look, 40)), secs: 0)
        var h = p.start.heading
        while h - stops[0].heading > 180 { h -= 360 }
        while h - stops[0].heading < -180 { h += 360 }
        p.start.heading = h
        return p
    }
    // ---- a smooth flight, frame by frame ----
    // Phases: hold low on the tee (1.2 s), climb away (2.2 s), glide down the hole (`seconds`, easing in and out,
    // facing the way the hole runs, averaged over 120 yds so bends turn gently), then the app settles on the green.
    static let holdSecs = 1.2, climbSecs = 2.2
    var travelSecs: Double = 6
    var s0 = 0.0, s1 = 0.0, totalYds = 0.0
    var totalSecs: Double { Self.holdSecs + Self.climbSecs + travelSecs }

    /// the way the hole runs at `s` yards: bearings averaged as vectors over ±60 yds
    func smoothHeading(at s: Double) -> Double {
        var x = 0.0, y = 0.0
        for k in stride(from: -60.0, through: 60.0, by: 10) {
            let a = max(0, min(totalYds, s + k - 10)), b = max(0, min(totalYds, s + k + 10))
            guard b > a else { continue }
            let br = FlyPath.bearing(FlyPath.point(points, at: a), FlyPath.point(points, at: b)) * .pi / 180
            let w = 1 - abs(k) / 70                      // nearer counts more
            x += sin(br) * w; y += cos(br) * w
        }
        return (atan2(x, y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
    private static func ease(_ u: Double) -> Double { let t = max(0, min(1, u)); return t * t * (3 - 2 * t) }
    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    private static func turn(_ from: Double, _ to: Double) -> Double { var d = (to - from).truncatingRemainder(dividingBy: 360); if d > 180 { d -= 360 }; if d < -180 { d += 360 }; return d }

    /// Where the camera is `t` seconds into the flight (until the glide ends): what it looks at, which way it faces,
    /// how far back it is (metres along the line of sight, MapKit's distance) and its tilt.
    func camera(at t: Double) -> (at: GeoPoint, heading: Double, metres: Double, pitch: Double) {
        if t <= Self.holdSecs { return (start.at, start.heading, Self.startMetres, Self.startPitch) }
        let first = FlyPath.point(points, at: s0), h0 = smoothHeading(at: s0)
        if t <= Self.holdSecs + Self.climbSecs {
            let u = Self.ease((t - Self.holdSecs) / Self.climbSecs)
            let c = GeoPoint(lat: Self.lerp(start.at.lat, first.lat, u), lng: Self.lerp(start.at.lng, first.lng, u))
            return (c, start.heading + Self.turn(start.heading, h0) * u, Self.lerp(Self.startMetres, cameraMetres, u), Self.lerp(Self.startPitch, 60, u))
        }
        let u = Self.ease((t - Self.holdSecs - Self.climbSecs) / travelSecs), s = Self.lerp(s0, s1, u)
        return (FlyPath.point(points, at: s), smoothHeading(at: s), cameraMetres, 60)
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
