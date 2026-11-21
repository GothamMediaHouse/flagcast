import SwiftUI
import MapKit
import Observation

#if os(macOS)
typealias PImage = NSImage
#else
typealias PImage = UIImage
#endif

/// The course photos: Apple Maps satellite pictures of the tournament's own course (no stock photos to license).
///   course(...)  the whole course: from the course map (every hole), the course's spot from Find the course, or a
///                search for its name and club
///   hole(...)    one hole from tee to green, turned so the green is at the top
/// Pictures are kept in Caches so each one is made once.
@MainActor
enum CourseImages {
    private static var memory: [String: PImage] = [:]
    private static var located: [String: CLLocationCoordinate2D] = [:]
    private static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("course-images")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// The whole course, for page headers and cards.
    static func course(id: String, name: String, club: String, at: LatLng?, map: CourseMap, size: CGSize = CGSize(width: 1600, height: 700)) async -> PImage? {
        let pts = map.holes.values.flatMap { [$0.tee, $0.m ?? $0.f].compactMap { $0 } }
        var center: CLLocationCoordinate2D?, span: Double = 1400
        if pts.count >= 2 {
            let lats = pts.map(\.lat), lngs = pts.map(\.lng)
            center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lngs.min()! + lngs.max()!) / 2)
            span = max(700, max((lats.max()! - lats.min()!) * 111_000, (lngs.max()! - lngs.min()!) * 111_000 * cos(center!.latitude * .pi / 180)) * 1.15)
        } else if let at { center = CLLocationCoordinate2D(latitude: at.lat, longitude: at.lng) }
        else { center = await locate(name: name, club: club) }
        guard let center else { return nil }
        let key = "course-\(id)-\(Int(center.latitude * 1e4))-\(Int(center.longitude * 1e4))-\(Int(span))-\(Int(size.width))"
        return await snapshot(key: key, camera: MKMapCamera(lookingAtCenter: center, fromDistance: span * 1.25, pitch: 0, heading: 0), size: size)
    }

    /// One hole, tee at the bottom and green at the top.
    static func hole(id: String, n: Int, h: HoleMap?, size: CGSize = CGSize(width: 900, height: 600)) async -> PImage? {
        guard let h, let t = h.tee, let g = h.m ?? h.f else { return nil }
        let center = CLLocationCoordinate2D(latitude: (t.lat + g.lat) / 2, longitude: (t.lng + g.lng) / 2)
        let len = Double(yards(t, g)) / 1.0936
        let key = "hole-\(id)-\(n)-\(Int(t.lat * 1e5))-\(Int(g.lat * 1e5))-\(Int(size.width))"
        return await snapshot(key: key, camera: MKMapCamera(lookingAtCenter: center, fromDistance: max(260, len * 1.7), pitch: 0, heading: bearing(t, g)), size: size)
    }

    /// A club with no tournament spot yet: its town.
    static func place(_ query: String, key: String, size: CGSize = CGSize(width: 900, height: 600)) async -> PImage? {
        guard let c = await locate(name: query, club: "") else { return nil }
        return await snapshot(key: "place-\(key)", camera: MKMapCamera(lookingAtCenter: c, fromDistance: 1800, pitch: 0, heading: 0), size: size)
    }

    private static func snapshot(key: String, camera: MKMapCamera, size: CGSize) async -> PImage? {
        if let m = memory[key] { return m }
        let file = dir.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_") + ".jpg")
        if let d = try? Data(contentsOf: file), let img = PImage(data: d) { memory[key] = img; return img }
        let o = MKMapSnapshotter.Options()
        o.camera = camera
        o.size = size
        o.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
        #if os(macOS)
        o.appearance = NSAppearance(named: .aqua)
        #else
        o.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        #endif
        guard let snap = try? await MKMapSnapshotter(options: o).start() else { return nil }
        let img = snap.image
        memory[key] = img
        #if os(macOS)
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) {
            try? jpg.write(to: file, options: .atomic)
        }
        #else
        if let jpg = img.jpegData(compressionQuality: 0.82) { try? jpg.write(to: file, options: .atomic) }
        #endif
        return img
    }

    /// Where a course is, from Apple Maps search (golf courses first).
    static func locate(name: String, club: String) async -> CLLocationCoordinate2D? {
        let q = [name.components(separatedBy: " · ").first ?? name, club].filter { !$0.isEmpty }.first ?? ""
        guard q.count >= 3 else { return nil }
        if let c = located[q] { return c }
        let r = MKLocalSearch.Request(); r.naturalLanguageQuery = q
        if #available(iOS 18.0, macOS 15.0, *) { r.pointOfInterestFilter = MKPointOfInterestFilter(including: [.golf]) }
        var item = try? await MKLocalSearch(request: r).start().mapItems.first
        if item == nil { let r2 = MKLocalSearch.Request(); r2.naturalLanguageQuery = q; item = try? await MKLocalSearch(request: r2).start().mapItems.first }
        guard let c = item?.placemark.coordinate else { return nil }
        located[q] = c
        return c
    }
}

/// A tournament's course picture, loaded once per tournament (and again when its course or map changes).
@MainActor @Observable
final class CoursePicture {
    var image: PImage?
    private var key = ""
    func load(_ ev: DeskEvent, id: String) {
        let k = "\(id)|\(ev.course.name)|\(ev.club)|\(ev.course.at?.lat ?? 0)|\(ev.map.holes.count)"
        guard k != key else { return }
        key = k
        Task { if let i = await CourseImages.course(id: id, name: ev.course.name, club: ev.club, at: ev.course.at, map: ev.map) { image = i } }
    }
}

/// A hole's picture for tiles and the team inspector.
struct HolePicture: View {
    let id: String, n: Int, h: HoleMap?, fallback: PImage?
    @State private var image: PImage?
    var body: some View {
        CourseHeroImage(image: image ?? fallback)
            .task(id: "\(n)-\(h?.tee?.lat ?? 0)") { image = await CourseImages.hole(id: id, n: n, h: h) }
    }
}
