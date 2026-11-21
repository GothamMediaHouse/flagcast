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

    func testEveryHoleFollowsItsLine() throws {
        XCTAssertEqual(Self.fx.holes.count, 18)
        var doglegs = 0
        for n in 1...18 {
            let h = try XCTUnwrap(Self.fx.holes[String(n)], "hole \(n)"), tee = try XCTUnwrap(h.tee), g = try XCTUnwrap(Geo.middle(h))
            let osm = try XCTUnwrap(Self.fx.osmLines[String(n)]).map { GeoPoint(lat: $0[0], lng: $0[1]) }
            let p = FlyPath.make(h, tee: tee, green: g, look: 260 * sin(60 * .pi / 180) * Geo.YD)
            // tee, every bend, green
            XCTAssertEqual(p.points.count, h.line.count + 2, "hole \(n): its bends are all on the path")
            // where the camera looks stays on the hole (the first stop is just behind the tee)
            for s in p.stops.dropFirst() { XCTAssertLessThan(off(s.at, osm), 30, "hole \(n): the camera looks along the hole") }
            // and it faces down the hole: within 30° of the real hole line's direction there
            let osmLen = FlyPath.length(osm)
            for (i, s) in p.stops.enumerated() {
                // where this look point is along the OSM line
                var best = (d: Double.infinity, at: 0.0)
                var k = 0.0; while k <= osmLen { let d = Geo.yds(s.at, FlyPath.point(osm, at: k)) ?? .infinity; if d < best.d { best = (d, k) }; k += 5 }
                let way = Geo.bearing(FlyPath.point(osm, at: max(0, best.at - 35)), FlyPath.point(osm, at: min(osmLen, best.at + 35)))
                XCTAssertLessThan(turn(s.heading, way), 30, "hole \(n): stop \(i) faces down the hole")
                XCTAssertLessThanOrEqual(Geo.yds(tee, s.at) ?? 0, (Geo.yds(tee, g) ?? 0) + 40, "hole \(n): never looks past the green")
            }
            // the camera starts just behind the tee
            let eye = Geo.offset(p.stops[0].at, yards: p.back, bearing: p.stops[0].heading + 180)
            XCTAssertLessThan(Geo.yds(eye, tee) ?? 999, 45, "hole \(n): starts behind the tee")
            let first = Geo.bearing(p.points[0], p.points[1]), last = Geo.bearing(p.points[p.points.count - 2], p.points[p.points.count - 1])
            if turn(first, last) > 20 {
                doglegs += 1
                // a straight tee-to-green flight would leave the hole here: the bend is well off that line
                let straight = [tee, g]
                XCTAssertGreaterThan(h.line.map { off($0, straight) }.max() ?? 0, 15, "hole \(n): a dogleg the old straight flight missed")
                XCTAssertGreaterThan(p.stops.map(\.heading).max()! - p.stops.map(\.heading).min()!, 15, "hole \(n): the camera turns at the dogleg")
            }
            XCTAssertGreaterThan(p.flySecs, 5.5); XCTAssertLessThan(p.flySecs, 7.5)
        }
        XCTAssertGreaterThanOrEqual(doglegs, 4, "Torrey Pines South has several doglegs")
    }

    func testHeadingsTurnTheShortWay() {
        // a hole running north that bends to the north-west: 10° then 350°, not a 340° spin the long way round
        let tee = GeoPoint(lat: 32.9, lng: -117.25)
        let bend = Geo.offset(tee, yards: 250, bearing: 10), green = Geo.offset(bend, yards: 150, bearing: 330)
        var h = try! JSONDecoder().decode(HoleMap.self, from: Data("{}".utf8))
        h.tee = tee; h.m = green; h.line = [bend]
        let p = FlyPath.make(h, tee: tee, green: green, look: 225)
        for (a, b) in zip(p.stops, p.stops.dropFirst()) { XCTAssertLessThanOrEqual(abs(a.heading - b.heading), 180) }
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
