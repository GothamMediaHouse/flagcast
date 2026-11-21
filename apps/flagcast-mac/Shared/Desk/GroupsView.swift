import SwiftUI
import MapKit

/// Where the groups are: each scorecard with GPS on sends its spot during the tournament (desk op "groups").
struct GroupsView: View {
    @Bindable var doc: DeskDoc
    @State private var groups: [Group] = []
    @State private var on = true
    @State private var camera: MapCameraPosition = .automatic
    @State private var picked: String?
    @AppStorage("map.3d") private var threeD = false

    struct Group: Identifiable, Hashable { var id: String; var name: String; var start: Int; var hole: Int; var at: GeoPoint; var acc: Double; var t: Double }

    var body: some View {
        VStack(spacing: 0) {
        MapHeader(title: "Where the groups are", sub: "\(groups.count) group\(groups.count == 1 ? "" : "s") on the course") {
            Toggle(isOn: $threeD) { Label("3D", systemImage: "view.3d") }.toggleStyle(.button).buttonStyle(GlassButton())
        }
        HStack(spacing: 0) {
            Map(position: $camera, selection: $picked) {
                ForEach(doc.ev.map.holes.keys.sorted(), id: \.self) { n in
                    if let g = doc.ev.map.holes[n]?.m { Annotation("", coordinate: g.coordinate) { Text("\(n)").font(.caption2.bold()).padding(3).background(.black.opacity(0.5), in: Circle()).foregroundStyle(.white) } }
                }
                ForEach(groups) { g in
                    Annotation(g.name, coordinate: g.at.coordinate) {
                        Text(g.hole > 0 ? "\(g.hole)" : "•").font(.caption.bold()).frame(minWidth: 26, minHeight: 26).padding(.horizontal, 4)
                            .background(stale(g) ? Color.gray : Color.blue, in: Capsule()).overlay(Capsule().stroke(.white, lineWidth: 2)).foregroundStyle(.white)
                    }.tag(g.id)
                }
            }
            .mapStyle(.imagery(elevation: threeD ? .realistic : .flat))
            .mapControls { MapCompass(); MapScaleView(); MapPitchToggle(); MapZoomStepper() }
            .overlay(alignment: .top) {
                if !on { Text("Group tracking is on only during the tournament: on its date, until the results are locked.").font(.callout).padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding() }
            }
            Divider()
            List(selection: $picked) {
                SwiftUI.Section("\(groups.count) group\(groups.count == 1 ? "" : "s") on the course") {
                    if groups.isEmpty { Text("No groups yet. They appear when a scorecard has GPS on.").foregroundStyle(.secondary) }
                    ForEach(groups) { g in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.name).fontWeight(.medium)
                            Text("\(g.hole > 0 ? "On hole \(g.hole)" : "On the course") · thru \(thru(g.id)) · started on \(g.start) · \(ago(g.t))").font(.caption).foregroundStyle(.secondary)
                        }.tag(g.id)
                    }
                }
            }
            .frame(width: 300)
        }
        }
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(20))
            }
        }
        .onChange(of: picked) { _, id in if let g = groups.first(where: { $0.id == id }) { withAnimation { camera = .camera(MapCamera(centerCoordinate: g.at.coordinate, distance: 500, heading: 0, pitch: threeD ? 50 : 0)) } } }
    }
    private func load() async {
        guard let r = await doc.day("groups") else { return }
        on = r["on"] as? Bool ?? false
        let now = r["now"] as? Double ?? Date().timeIntervalSince1970 * 1000
        groups = (r["groups"] as? [[String: Any]] ?? []).compactMap { g in
            guard let at = g["at"] as? [Double], at.count == 2 else { return nil }
            return Group(id: g["team"] as? String ?? UUID().uuidString, name: g["name"] as? String ?? "Group", start: g["start"] as? Int ?? 1, hole: g["hole"] as? Int ?? 0,
                         at: GeoPoint(lat: at[0], lng: at[1]), acc: g["acc"] as? Double ?? 0, t: (g["t"] as? Double ?? now) - now + Date().timeIntervalSince1970 * 1000)
        }
        if camera == .automatic, let first = groups.first { camera = .camera(MapCamera(centerCoordinate: first.at.coordinate, distance: 2500, heading: 0, pitch: 0)) }
        else if camera == .automatic, let any = doc.ev.map.holes.values.compactMap({ $0.m }).first { camera = .camera(MapCamera(centerCoordinate: any.coordinate, distance: 2500, heading: 0, pitch: 0)) }
    }
    private func stale(_ g: Group) -> Bool { Date().timeIntervalSince1970 * 1000 - g.t > 10 * 60_000 }
    private func ago(_ t: Double) -> String { let m = Int((Date().timeIntervalSince1970 * 1000 - t) / 60_000); return m < 1 ? "just now" : "\(m) min ago" }
    private func thru(_ team: String) -> String {
        let s = doc.live?.scores[team] ?? [:]
        let done = (0..<18).filter { i in !s.isEmpty && s.values.allSatisfy { i < $0.count && $0[i] != nil } }.count
        return "\(done)"
    }
}
