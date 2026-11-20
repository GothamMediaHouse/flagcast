import Foundation
import CoreLocation
import Observation

// Hole GPS (matches public/golf/gps.js): yardages from the phone's location to the green and hazards, from the
// club's course map (state.map). From the tee when the phone isn't on the hole yet.

enum Geo {
    static let R = 6371008.8, YD = 1.0936133

    /// Yards between two points (haversine, like gps.js).
    static func yds(_ a: GeoPoint?, _ b: GeoPoint?) -> Double? {
        guard let a, let b else { return nil }
        let t = Double.pi / 180, dla = (b.lat - a.lat) * t, dlo = (b.lng - a.lng) * t
        let h = pow(sin(dla / 2), 2) + cos(a.lat * t) * cos(b.lat * t) * pow(sin(dlo / 2), 2)
        return 2 * R * asin(min(1, sqrt(h))) * YD
    }

    static func middle(_ h: HoleMap?) -> GeoPoint? {
        guard let h else { return nil }
        if let m = h.m { return m }
        if let f = h.f, let b = h.b { return GeoPoint(lat: (f.lat + b.lat) / 2, lng: (f.lng + b.lng) / 2) }
        return h.f ?? h.b
    }

    static func mapped(_ s: EventState) -> Bool { s.map.holes.values.contains { middle($0) != nil } }

    /// Where the yardages are from: the phone when it's on this hole, otherwise the tee.
    static func origin(_ h: HoleMap, _ me: GeoPoint?) -> (at: GeoPoint, me: Bool)? {
        if let me, let g = middle(h), let toG = yds(me, g) {
            let len = h.tee.flatMap { yds($0, g) } ?? 600
            if toG <= len + 40 && toG < 700 { return (me, true) }
        }
        return h.tee.map { ($0, false) }
    }

    struct HazardYards: Identifiable { var id: String; var name: String; var k: String; var reach: Int; var carry: Int? }
    struct Yardages { var f: Int?; var m: Int?; var b: Int?; var hz: [HazardYards] }

    static let hazardName = ["bunker": "Bunker", "water": "Water", "trees": "Trees", "layup": "Layup", "other": "Hazard"]

    /// Front / middle / back and the hazards still ahead (ones behind you are left out), from a point.
    static func yardages(_ h: HoleMap, from: GeoPoint) -> Yardages {
        let g = middle(h), toG = yds(from, g)
        func r(_ p: GeoPoint?) -> Int? { yds(from, p).map { Int(jsRound($0)) } }
        let hz = h.hz.compactMap { z -> HazardYards? in
            if let toG, let far = yds(z.c ?? z.p, g), far > toG + 5 { return nil }
            return HazardYards(id: z.id, name: z.n.isEmpty ? (hazardName[z.k] ?? "Hazard") : z.n, k: z.k, reach: r(z.p) ?? 0, carry: r(z.c))
        }.sorted { $0.reach < $1.reach }
        return Yardages(f: r(h.f), m: r(g), b: r(h.b), hz: hz)
    }

    /// Group tracking runs only while the tournament is on: on its date (US time zones: 04:00 UTC that day to
    /// 11:00 UTC the next) and until the results are final. The server checks the same thing.
    static func trackingOn(_ s: EventState, now: Date = Date()) -> Bool {
        guard !s.locked else { return false }
        let parts = s.date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, s.date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return false }
        var c = DateComponents(); c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        guard let d = cal.date(from: c) else { return false }
        let t = now.timeIntervalSince(d)
        return t >= 4 * 3600 && t <= 35 * 3600
    }

    /// Compass bearing (degrees) from a to b, for turning the course view so the green is at the top.
    static func bearing(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let t = Double.pi / 180, la1 = a.lat * t, la2 = b.lat * t, dlo = (b.lng - a.lng) * t
        let y = sin(dlo) * cos(la2), x = cos(la1) * sin(la2) - sin(la1) * cos(la2) * cos(dlo)
        return (atan2(y, x) / t + 360).truncatingRemainder(dividingBy: 360)
    }

    /// The point `yards` from a, on compass bearing `deg` (for the carry arcs).
    static func offset(_ a: GeoPoint, yards: Double, bearing deg: Double) -> GeoPoint {
        let t = Double.pi / 180, d = yards / YD / R, br = deg * t, la1 = a.lat * t, lo1 = a.lng * t
        let la2 = asin(sin(la1) * cos(d) + cos(la1) * sin(d) * cos(br))
        let lo2 = lo1 + atan2(sin(br) * sin(d) * cos(la1), cos(d) - sin(la1) * sin(la2))
        return GeoPoint(lat: la2 / t, lng: lo2 / t)
    }
}

extension GeoPoint {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
    init(_ c: CLLocationCoordinate2D) { self.init(lat: c.latitude, lng: c.longitude) }
}

/// The phone's location while hole GPS is on. "Use my GPS" is remembered, like the website.
@MainActor @Observable
final class Locator: NSObject, CLLocationManagerDelegate {
    static let shared = Locator()
    private let manager = CLLocationManager()
    private(set) var fix: (at: GeoPoint, acc: Int, t: Date)?
    private(set) var error: String?
    private(set) var on = UserDefaults.standard.bool(forKey: "flagcast.gps")
    @ObservationIgnored var onFix: [String: (GeoPoint, Int) -> Void] = [:]

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 2
        manager.activityType = .fitness
    }

    func start() {
        on = true
        UserDefaults.standard.set(true, forKey: "flagcast.gps")
        error = nil
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: error = "Location is off for Flagcast. Turn it on in Settings to see yardages from where you are."
        default: manager.startUpdatingLocation()
        }
    }
    /// Keep following while a scorecard is open and GPS was switched on.
    func resume() { if on { start() } }
    func pause() { manager.stopUpdatingLocation() }
    func stop() {
        on = false
        UserDefaults.standard.set(false, forKey: "flagcast.gps")
        manager.stopUpdatingLocation()
        fix = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Task { @MainActor in
            switch m.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: if self.on { m.startUpdatingLocation() }
            case .denied, .restricted: if self.on { self.error = "Location is off for Flagcast. Turn it on in Settings to see yardages from where you are." }
            default: break
            }
        }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let l = locs.last, l.horizontalAccuracy >= 0 else { return }
        Task { @MainActor in
            let p = GeoPoint(l.coordinate), acc = Int((l.horizontalAccuracy * Geo.YD).rounded())
            self.fix = (p, acc, Date())
            self.error = nil
            for f in self.onFix.values { f(p, acc) }
        }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError e: Error) {
        Task { @MainActor in
            if (e as? CLError)?.code == .denied { self.error = "Location is off for Flagcast. Turn it on in Settings to see yardages from where you are." }
            else if self.fix == nil { self.error = "Can’t find your spot yet. Yardages show once the phone has GPS." }
        }
    }
}
