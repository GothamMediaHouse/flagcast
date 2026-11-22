import XCTest
@testable import Flagcast

/// "Fly the hole" follows the hole as it's played. Checked on Torrey Pines South (the sample tournament's course,
/// from OpenStreetMap: torrey-south.json, made by the same importer the map page uses), including its doglegs.
final class FlyTests: XCTestCase {
    struct Fixture: Decodable { let holes: [String: HoleMap]; let osmLines: [String: [[Double]]] }
    static let fx: Fixture = {
        let u = Bundle(for: FlyTests.self).url(forResource: "torrey-south", withExtension: "json")!
        return try! JSONDecoder().decode(Fixture.self, from: try! Data(contentsOf: u))
    }()
    /// yards from p to the nearest point of a polyline
    func off(_ p: GeoPoint, _ line: [GeoPoint]) -> Double {
        var best = Double.infinity
        for (a, b) in zip(line, line.dropFirst()) {
            let n = 40
            for i in 0...n { let t = Double(i) / Double(n); best = min(best, Geo.yds(p, GeoPoint(lat: a.lat + (b.lat - a.lat) * t, lng: a.lng + (b.lng - a.lng) * t)) ?? .infinity) }
        }
        return best
    }
    func turn(_ a: Double, _ b: Double) -> Double { let d = abs(a - b).truncatingRemainder(dividingBy: 360); return min(d, 360 - d) }

    /// the camera's eye: behind the point it looks at, along its heading
    func eye(_ c: (at: GeoPoint, heading: Double, metres: Double, pitch: Double)) -> GeoPoint {
        Geo.offset(c.at, yards: c.metres * sin(c.pitch * .pi / 180) * Geo.YD, bearing: c.heading + 180)
    }

    func testEveryHoleFollowsItsLine() throws {
        XCTAssertEqual(Self.fx.holes.count, 18)
        var doglegs = 0
        for n in 1...18 {
            let h = try XCTUnwrap(Self.fx.holes[String(n)], "hole \(n)"), tee = try XCTUnwrap(h.tee), g = try XCTUnwrap(Geo.middle(h))
            let osm = try XCTUnwrap(Self.fx.osmLines[String(n)]).map { GeoPoint(lat: $0[0], lng: $0[1]) }
            let p = FlyPath.make(h, tee: tee, green: g)
            // tee, every bend, green
            XCTAssertEqual(p.points.count, h.line.count + 2, "hole \(n): its bends are all on the path")
            XCTAssertGreaterThanOrEqual(p.travelSecs, 7); XCTAssertLessThanOrEqual(p.travelSecs, 22)
            // it opens low on the tee box, looking down the hole
            let c0 = p.camera(at: 0)
            XCTAssertLessThan(Geo.yds(eye(c0), tee) ?? 999, 15, "hole \(n): opens on the tee box")
            XCTAssertLessThan(p.height(at: 0), 30, "hole \(n): opens low (under 30 m up)")
            var t = 0.0, last = c0, heights: [Double] = [], headings: [Double] = []
            while t <= p.totalSecs {
                let c = p.camera(at: t), e = eye(c)
                // what it looks at stays on the hole and never past the green; the camera flies over the hole
                XCTAssertLessThan(off(c.at, osm), 30, "hole \(n) at \(t) s: looks along the hole")
                XCTAssertLessThanOrEqual(Geo.yds(tee, c.at) ?? 0, (Geo.yds(tee, g) ?? 0) + 40, "hole \(n): never looks past the green")
                XCTAssertLessThan(min(off(e, osm), Geo.yds(e, tee) ?? 999), 35, "hole \(n) at \(t) s: the camera is over the hole")
                // smooth: no jumps, no snapping round
                XCTAssertLessThan(Geo.yds(eye(last), e) ?? 999, 4.5, "hole \(n) at \(t) s: the camera glides")
                XCTAssertLessThan(turn(last.heading, c.heading), 3, "hole \(n) at \(t) s: the camera turns gently")
                XCTAssertLessThan(abs(last.pitch - c.pitch), 0.6, "hole \(n) at \(t) s: the tilt changes gently")
                // inside what Apple's 3D map will do, so it never stops the camera short
                XCTAssertLessThanOrEqual(c.pitch, 74); XCTAssertGreaterThanOrEqual(c.metres, 82)
                heights.append(p.height(at: t)); headings.append(c.heading)
                last = c; t += 0.1
            }
            // low all the way, like a drone: never above 50 m, and it ends low, looking at the green
            XCTAssertLessThan(heights.max()!, 50, "hole \(n): stays low")
            XCTAssertGreaterThan(heights.last!, 12, "hole \(n): ends above the green"); XCTAssertLessThan(heights.last!, 40, "hole \(n): ends low")
            XCTAssertLessThan(Geo.yds(last.at, g) ?? 999, 3, "hole \(n): ends looking at the green")
            let first = Geo.bearing(p.points[0], p.points[1]), lastB = Geo.bearing(p.points[p.points.count - 2], p.points[p.points.count - 1])
            if turn(first, lastB) > 20 {
                doglegs += 1
                // a straight tee-to-green flight would leave the hole here: the bend is well off that line
                XCTAssertGreaterThan(h.line.map { off($0, [tee, g]) }.max() ?? 0, 15, "hole \(n): a dogleg the old straight flight missed")
                XCTAssertGreaterThan(headings.map { turn($0, headings[0]) }.max()!, 15, "hole \(n): the camera turns at the dogleg")
            }
        }
        XCTAssertGreaterThanOrEqual(doglegs, 4, "Torrey Pines South has several doglegs")
    }

    func testEvenSpeedWithEasedEnds() {
        XCTAssertEqual(FlyPath.progress(0), 0, accuracy: 1e-9); XCTAssertEqual(FlyPath.progress(1), 1, accuracy: 1e-9)
        var prev = 0.0, steps: [Double] = []
        for i in 1...100 { let x = FlyPath.progress(Double(i) / 100); XCTAssertGreaterThanOrEqual(x, prev); steps.append(x - prev); prev = x }
        // starts and ends nearly still, cruises at one speed in the middle
        XCTAssertLessThan(steps.first!, 0.002); XCTAssertLessThan(steps.last!, 0.002)
        XCTAssertEqual(steps[30], steps[60], accuracy: 1e-9)
    }

    func testHeadingsTurnTheShortWay() {
        // a hole running north that bends to the north-west: 10° then 350°, not a 340° spin the long way round
        let tee = GeoPoint(lat: 32.9, lng: -117.25)
        let bend = Geo.offset(tee, yards: 250, bearing: 10), green = Geo.offset(bend, yards: 150, bearing: 330)
        var h = try! JSONDecoder().decode(HoleMap.self, from: Data("{}".utf8))
        h.tee = tee; h.m = green; h.line = [bend]
        let p = FlyPath.make(h, tee: tee, green: green)
        var t = 0.0, last = p.camera(at: 0).heading
        while t <= p.totalSecs { let hd = p.camera(at: t).heading; XCTAssertLessThan(turn(last, hd), 3); last = hd; t += 0.1 }
    }

    func testNoBendsFliesStraightAndLayupsCount() {
        let tee = GeoPoint(lat: 32.9, lng: -117.25), green = Geo.offset(tee, yards: 400, bearing: 90)
        var h = try! JSONDecoder().decode(HoleMap.self, from: Data("{}".utf8))
        h.tee = tee; h.m = green
        XCTAssertEqual(FlyPath.holePath(h, tee: tee, green: green).count, 2)
        // no line from the map: a lay-up spot marks the corner
        let corner = Geo.offset(tee, yards: 240, bearing: 60)
        h.hz = [Hazard(id: "l1", k: "layup", n: "Lay up", p: corner, c: nil)]
        XCTAssertEqual(FlyPath.holePath(h, tee: tee, green: green), [tee, corner, green])
    }
}
