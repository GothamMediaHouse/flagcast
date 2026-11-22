import Foundation

/// The path "Fly the hole" follows: the hole as it's played, not a straight line from tee to green.
/// Its bends come from the course map's line (OpenStreetMap's hole line, kept when the course was mapped); a hole
/// without one uses its lay-up spots, and failing that flies straight. Kept free of MapKit so tests can check it.
struct FlyPath: Equatable {
    var points: [GeoPoint]     // tee, bends, green (as mapped)
    var path: [GeoPoint]       // the same with its corners rounded off: the line the camera flies along
    var totalYds = 0.0         // tee to green along the path
    var travelSecs = 8.0       // the glide from the tee to the green

    // ---- the look, from Golf Digest's "Every Hole at Pinehurst No. 2" drone flyovers ----
    // The drone sits on the tee box nearly level with the golfer, then pushes off down the middle of the hole at an
    // even speed, rising a little and tilted just below the horizon. It eases off as the green fills the frame and
    // ends low, short of the green, looking straight at it. One continuous move, no cuts, no swoops.
    // Apple's 3D map won't go lower than that: it stops tilting at 74° and won't come closer than about 81 m to
    // what it looks at (checked on the Mac, Torrey Pines South), so the camera keeps just inside those limits,
    // where it's still smooth, which puts it some 25 to 45 m up.
    static let startPitch = 73.0, startLook = 85.0      // on the tee: degrees from straight down; yards ahead it looks
    static let cruisePitch = 72.0, cruiseLook = 150.0   // down the fairway: ~45 m up, looking 150 yds ahead
    static let endPitch = 68.0, endLook = 90.0          // at the green: ~33 m up, 90 yds short of the middle
    static let nearest = 88.0                            // metres: never asks Apple's map to come closer than this
    static let behindTee = 10.0                          // the camera starts this far behind the tee marker
    static let speed = 24.0                              // yds a second, cruising (the video flies at ~13)
    static let holdSecs = 1.0, arriveSecs = 1.6          // still on the tee before it moves; still on the green at the end
    var totalSecs: Double { Self.holdSecs + travelSecs + Self.arriveSecs }

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

    /// The hole from where you are to the green, round its doglegs: you, the bends still ahead of you, the green.
    static func ahead(_ h: HoleMap, from: GeoPoint, green g: GeoPoint) -> [GeoPoint] {
        let left = yds(from, g) ?? 0
        let bends = h.line.filter { b in (yds(b, g) ?? 0) < left - 20 && (yds(from, b) ?? 0) > 20 }
            .sorted { (yds($0, g) ?? 0) > (yds($1, g) ?? 0) }
        return [from] + bends + [g]
    }
    /// Where the hole's line (`ahead`) is `d` yards from you as the crow flies: where a 50-yard arc crosses the fairway.
    static func cross(_ pts: [GeoPoint], from: GeoPoint, yards d: Double) -> GeoPoint? {
        let total = length(pts)
        var s = 0.0
        while s <= total { let p = point(pts, at: s); if (yds(from, p) ?? 0) >= d { return p }; s += 2 }
        return nil
    }

    /// The point `s` yards along a path, carried on past either end in a straight line.
    static func along(_ pts: [GeoPoint], at s: Double, total: Double) -> GeoPoint {
        if s < 0, pts.count > 1 { return offset(pts[0], yards: -s, bearing: bearing(pts[1], pts[0])) }
        if s > total, pts.count > 1 { return offset(pts[pts.count - 1], yards: s - total, bearing: bearing(pts[pts.count - 2], pts[pts.count - 1])) }
        return point(pts, at: s)
    }
    /// Corners rounded off (Chaikin, three passes), ends kept, so the camera banks round a dogleg instead of
    /// snapping to a new direction at the corner.
    static func rounded(_ pts: [GeoPoint]) -> [GeoPoint] {
        var p = pts
        for _ in 0..<3 where p.count > 2 {
            var q = [p[0]]
            for (a, b) in zip(p, p.dropFirst()) {
                q.append(GeoPoint(lat: a.lat * 0.75 + b.lat * 0.25, lng: a.lng * 0.75 + b.lng * 0.25))
                q.append(GeoPoint(lat: a.lat * 0.25 + b.lat * 0.75, lng: a.lng * 0.25 + b.lng * 0.75))
            }
            q.append(p[p.count - 1])
            p = q
        }
        return p
    }

    static func make(_ h: HoleMap, tee: GeoPoint, green g: GeoPoint) -> FlyPath {
        let pts = holePath(h, tee: tee, green: g)
        var p = FlyPath(points: pts, path: rounded(pts))
        p.totalYds = max(40, length(p.path))
        // an even cruise, with the speeding up and slowing down on top; a short par 3 still takes 7 s
        p.travelSecs = min(22, max(7, p.travelYds / Self.speed + 2.4))
        return p
    }

    /// how far ahead the camera looks once it's flying: 150 yds, less on a short hole so the green isn't in the
    /// opening shot already
    var cruiseLook: Double { max(Self.endLook, min(Self.cruiseLook, totalYds * 0.5)) }
    var endLook: Double { min(Self.endLook, totalYds * 0.45) }
    /// the camera's run along the ground: from behind the tee to `endLook` short of the green
    var travelYds: Double { max(20, totalYds - endLook + Self.behindTee) }

    private static func smooth(_ u: Double) -> Double { let t = max(0, min(1, u)); return t * t * (3 - 2 * t) }
    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    /// How far along the run the camera is, 0...1, `u` of the way through the glide: it speeds up gently over the
    /// first 18%, holds an even speed, and slows over the last 30% (velocity eased with half a cosine each end).
    static func progress(_ u: Double) -> Double {
        let A = 0.18, D = 0.30, v = 1 / (1 - (A + D) / 2), t = max(0, min(1, u))
        if t < A { return v * (t / 2 - A / (2 * .pi) * sin(.pi * t / A)) }
        if t > 1 - D { let r = 1 - t; return 1 - v * (r / 2 - D / (2 * .pi) * sin(.pi * r / D)) }
        return v * (A / 2 + (t - A))
    }

    /// Where the camera is `s` yards along its run (its eye on the ground below it, what it looks at, its tilt).
    func shot(_ s: Double) -> (eye: GeoPoint, look: GeoPoint, pitch: Double) {
        let se = s - Self.behindTee                                 // the eye, yards from the tee
        let climb = Self.smooth(s / min(140, max(40, travelYds * 0.35)))
        let ahead = FlyPath.lerp(Self.startLook + Self.behindTee, cruiseLook, climb)
        let sl = min(totalYds, se + ahead)                          // looks down the hole, never past the green
        // closing on the green: the look stays on it and the camera comes down to `endLook` short of it
        let left = totalYds - se, near = Self.smooth(1 - (left - endLook) / max(40, cruiseLook - endLook))
        var pitch = FlyPath.lerp(Self.startPitch, Self.cruisePitch, climb)
        pitch = FlyPath.lerp(pitch, Self.endPitch, near)
        return (FlyPath.along(path, at: se, total: totalYds), FlyPath.point(path, at: sl), pitch)
    }

    /// The camera `t` seconds into the flight, as MapKit wants it: the point it looks at, which way it faces, its
    /// distance from that point (metres along the line of sight) and its tilt. The eye and the look point both stay
    /// on the hole, and the heading is the line between them, so it turns smoothly round a dogleg.
    func camera(at t: Double) -> (at: GeoPoint, heading: Double, metres: Double, pitch: Double) {
        let u = (t - Self.holdSecs) / travelSecs
        let c = shot(FlyPath.progress(u) * travelYds)
        let ground = max(20, FlyPath.yds(c.eye, c.look) ?? 20) / FlyPath.YD
        return (c.look, FlyPath.bearing(c.eye, c.look), max(Self.nearest, ground / sin(c.pitch * .pi / 180)), c.pitch)
    }
    /// how high the camera is, in metres, `t` seconds in
    func height(at t: Double) -> Double { let c = camera(at: t); return c.metres * cos(c.pitch * .pi / 180) }
}
