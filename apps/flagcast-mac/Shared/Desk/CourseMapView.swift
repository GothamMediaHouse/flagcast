import SwiftUI
import MapKit

/// The course map for hole GPS, on Apple's satellite imagery (flat or 3D): per hole the tee, the front / middle /
/// back of the green and hazards (where you reach it, what carries it). Click to place, drag to move. It saves as
/// you go, and the club keeps it for its next tournament. "Fill in the holes" maps it from OpenStreetMap.
struct CourseMapView: View {
    @Bindable var doc: DeskDoc
    @State private var hole = 1
    @State private var tool: Tool? = .tee
    @State private var camera: MapCameraPosition = .automatic
    @AppStorage("map.3d") private var threeD = false
    @State private var saveTask: Task<Void, Never>?
    @State private var saving = false
    @State private var note: String?
    @State private var search = ""
    @State private var busy = false
    @State private var confirmRedo = false

    enum Tool: Hashable { case tee, f, m, b, hzP(String), hzC(String)
        var label: String { switch self { case .tee: "tee"; case .f: "front of the green"; case .m: "middle of the green"; case .b: "back of the green"; case .hzP: "where the hazard starts (the near edge)"; case .hzC: "the far edge, where a shot carries it" } }
    }
    private var h: HoleMap { doc.ev.map.holes[hole] ?? HoleMap() }
    private func set(_ f: (inout HoleMap) -> Void) { var x = h; f(&x); doc.ev.map.holes[hole] = x; scheduleSave() }

    var body: some View {
        VStack(spacing: 0) {
            MapHeader(title: "Course map", sub: doc.ev.course.name.isEmpty ? doc.ev.name : doc.ev.course.name) {
                Text(saving ? "Saving…" : "Saves as you go").font(.system(size: 12, weight: .semibold)).foregroundStyle(FC.onGreenMuted)
                Toggle(isOn: $threeD) { Label("3D", systemImage: "cube") }.toggleStyle(.button).buttonStyle(GlassButton()).help("Show the course in 3D where Apple has it")
            }
            holeStrip.background(FC.green).environment(\.colorScheme, .dark)
            MapReader { proxy in
                Map(position: $camera, interactionModes: .all) {
                    // the other holes, faint, to find your way around
                    ForEach(doc.ev.map.holes.keys.sorted().filter { $0 != hole }, id: \.self) { n in
                        if let o = doc.ev.map.holes[n], let g = o.m ?? o.f {
                            Annotation("", coordinate: g.coordinate) {
                                Button { pick(n) } label: { Text("\(n)").font(.caption2.bold()).padding(4).background(.black.opacity(0.55), in: Circle()).foregroundStyle(.white) }.buttonStyle(.plain)
                            }
                        }
                    }
                    if let t = h.tee, let g = h.m ?? h.f { MapPolyline(coordinates: [t.coordinate, g.coordinate]).stroke(.white.opacity(0.85), lineWidth: 2) }
                    ForEach(h.hz) { z in
                        if let c = z.c { MapPolyline(coordinates: [z.p.coordinate, c.coordinate]).stroke(hazardColor(z.k), lineWidth: 3) }
                        pin(z.p, color: hazardColor(z.k), text: "", proxy: proxy) { p in set { x in if let i = x.hz.firstIndex(where: { $0.id == z.id }) { x.hz[i].p = p } } }
                        if let c = z.c { pin(c, color: hazardColor(z.k).opacity(0.8), text: "", proxy: proxy) { p in set { x in if let i = x.hz.firstIndex(where: { $0.id == z.id }) { x.hz[i].c = p } } } }
                    }
                    if let p = h.tee { pin(p, color: .fcFlag, text: "T", proxy: proxy) { q in set { $0.tee = q } } }
                    if let p = h.f { pin(p, color: .white, text: "F", proxy: proxy) { q in set { $0.f = q } } }
                    if let p = h.b { pin(p, color: .white, text: "B", proxy: proxy) { q in set { $0.b = q } } }
                    if let p = h.m { pin(p, color: .red, text: "⚑", proxy: proxy) { q in set { $0.m = q } } }
                    UserAnnotation()
                }
                .mapStyle(.imagery(elevation: threeD ? .realistic : .flat))
                .mapControls { MapCompass(); MapScaleView(); MapPitchToggle(); MapZoomStepper() }
                .coordinateSpace(.named("map"))
                .onMapCameraChange(frequency: .onEnd) { ctx in lastRegion = ctx.region }
                .onTapGesture(coordinateSpace: .named("map")) { pt in
                    guard let c = proxy.convert(pt, from: .named("map")) else { return }
                    place(GeoPoint(lat: c.latitude, lng: c.longitude))
                }
                .overlay(alignment: .top) {
                    if let tool { Text("Click the map to set the \(tool.label).").font(.callout.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 6).background(.regularMaterial, in: Capsule()).padding(10) }
                }
                .overlay(alignment: .bottomLeading) {
                    if doc.ev.map.src == "osm" { Text(OSM.credit).font(.caption2).padding(4).background(.black.opacity(0.4)).foregroundStyle(.white).padding(6) }
                }
            }
        }
        .inspector(isPresented: .constant(true)) { inspector.inspectorColumnWidth(min: 300, ideal: 340, max: 420) }
        .onAppear { hole = firstOpenHole(); fit() }
        .onChange(of: hole) { _, _ in fit() }
        .onChange(of: threeD) { _, _ in fit() }
        .confirmationDialog("Map every hole again from OpenStreetMap?", isPresented: $confirmRedo) {
            Button("Redo Every Hole", role: .destructive) { auto(all: true) }
        } message: { Text("Holes you placed or moved by hand are replaced.") }
    }

    // ---- the hole strip ----
    private var holeStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(doc.ev.course.holes, id: \.n) { x in
                    let o = doc.ev.map.holes[x.n], done = o?.tee != nil && (o?.m ?? o?.f) != nil
                    Button { pick(x.n) } label: {
                        VStack(spacing: 0) { Text("\(x.n)").font(.callout.bold()); Text("par \(x.par)").font(.caption2).foregroundStyle(.secondary) }
                            .frame(width: 40, height: 34)
                            .background(x.n == hole ? Color.accentColor.opacity(0.25) : done ? Color.green.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(alignment: .topTrailing) { if done { Image(systemName: "checkmark.circle.fill").font(.system(size: 9)).foregroundStyle(.green).offset(x: -2, y: 2) } }
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
    }

    // ---- the panel ----
    @ViewBuilder private var inspector: some View {
        let par = doc.ev.course.holes.first { $0.n == hole }?.par ?? 4
        Form {
            SwiftUI.Section("Hole \(hole) · par \(par)") {
                Picker("Place", selection: $tool) {
                    Text("Nothing (move the map)").tag(Tool?.none)
                    Text("Tee").tag(Tool?.some(.tee)); Text("Front of the green").tag(Tool?.some(.f))
                    Text("Middle of the green").tag(Tool?.some(.m)); Text("Back of the green").tag(Tool?.some(.b))
                }
                if let t = h.tee, let g = h.m ?? h.f { LabeledContent("Tee to the middle", value: "\(yards(t, g)) yds") }
                if let f = h.f, let b = h.b { LabeledContent("Green depth", value: "\(yards(f, b)) yds") }
                HStack { Button("Clear This Hole", role: .destructive) { doc.ev.map.holes[hole] = nil; tool = .tee; scheduleSave() }; Spacer(); Button("Show the Hole") { fit() } }
            }
            SwiftUI.Section("Hazards") {
                ForEach(h.hz) { z in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Picker("", selection: Binding(get: { z.k }, set: { k in set { x in if let i = x.hz.firstIndex(where: { $0.id == z.id }) { x.hz[i].k = k } } })) {
                                Text("Bunker").tag("bunker"); Text("Water").tag("water"); Text("Trees").tag("trees"); Text("Layup").tag("layup"); Text("Other").tag("other")
                            }.labelsHidden().frame(width: 100)
                            TextField("Name", text: Binding(get: { z.n }, set: { n in set { x in if let i = x.hz.firstIndex(where: { $0.id == z.id }) { x.hz[i].n = String(n.prefix(40)) } } }), prompt: Text("Left fairway bunker"))
                            Button(role: .destructive) { set { $0.hz.removeAll { $0.id == z.id } } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                        }
                        HStack { Button(z.c == nil ? "Add Carry" : "Move Carry") { tool = .hzC(z.id) }.controlSize(.small)
                            if let t = h.tee { Text("\(yards(t, z.p))\(z.c.map { " · carry \(yards(t, $0))" } ?? "") yds from the tee").font(.caption).foregroundStyle(.secondary) } }
                    }
                }
                Menu { ForEach(["bunker", "water", "trees", "layup", "other"], id: \.self) { k in Button(k.capitalized) { addHazard(k) } } } label: { Label("Add Hazard", systemImage: "plus") }
            }
            SwiftUI.Section {
                HStack {
                    TextField("Course name or town", text: $search).onSubmit(findPlace)
                    Button("Find", action: findPlace).disabled(search.count < 3)
                }
                HStack {
                    Button("Fill In the Holes") { auto(all: false) }.buttonStyle(.borderedProminent).disabled(busy)
                    if !doc.ev.map.holes.isEmpty { Button("Redo Every Hole") { confirmRedo = true }.disabled(busy) }
                    if busy { ProgressView().controlSize(.small) }
                }
                if let note { Text(note).font(.callout).foregroundStyle(.secondary) }
            } header: { Text("Map it automatically") } footer: {
                Help("Find the course so it fills the map, then Fill In the Holes maps every hole it can from OpenStreetMap: tees, greens, bunkers and water. Check each hole afterwards and drag anything that’s off.")
            }
        }
        .formStyle(.grouped)
    }

    // ---- placing ----
    @MapContentBuilder
    private func pin(_ p: GeoPoint, color: Color, text: String, proxy: MapProxy, moved: @escaping (GeoPoint) -> Void) -> some MapContent {
        Annotation("", coordinate: p.coordinate) {
            ZStack {
                Circle().fill(color).frame(width: text.isEmpty ? 14 : 22, height: text.isEmpty ? 14 : 22).overlay(Circle().stroke(.black.opacity(0.6), lineWidth: 1.5))
                if !text.isEmpty { Text(text).font(.system(size: 11, weight: .heavy)).foregroundStyle(color == .white || color == .fcFlag ? .black : .white) }
            }
            .shadow(radius: 2)
            .gesture(DragGesture(coordinateSpace: .named("map")).onEnded { v in
                if let c = proxy.convert(v.location, from: .named("map")) { moved(GeoPoint(lat: c.latitude, lng: c.longitude)) }
            })
            .help("Drag to move")
        }
    }
    private func place(_ p: GeoPoint) {
        guard let tool else { return }
        switch tool {
        case .tee: set { $0.tee = p }
        case .f: set { $0.f = p }
        case .m: set { $0.m = p }
        case .b: set { $0.b = p }
        case .hzP(let id): set { x in if let i = x.hz.firstIndex(where: { $0.id == id }) { x.hz[i].p = p } }; self.tool = .hzC(id); return
        case .hzC(let id): set { x in if let i = x.hz.firstIndex(where: { $0.id == id }) { x.hz[i].c = p } }; self.tool = nil; return
        }
        // next thing still missing on this hole
        let x = h
        self.tool = x.tee == nil ? .tee : x.f == nil ? .f : x.m == nil ? .m : x.b == nil ? .b : nil
    }
    private func addHazard(_ k: String) {
        let z = Hazard(id: Ids.make(), k: k, n: "", p: h.m ?? h.tee ?? GeoPoint(lat: 0, lng: 0), c: nil)
        set { $0.hz.append(z) }
        tool = .hzP(z.id)
    }
    private func pick(_ n: Int) {
        hole = n
        let x = doc.ev.map.holes[n] ?? HoleMap()
        tool = x.tee == nil ? .tee : x.f == nil ? .f : x.m == nil ? .m : x.b == nil ? .b : nil
    }
    private func firstOpenHole() -> Int { doc.ev.course.holes.map(\.n).first { n in let x = doc.ev.map.holes[n]; return x?.tee == nil || (x?.m ?? x?.f) == nil } ?? 1 }

    /// Frame the hole with the green at the top (or the course, or the club's spot).
    private func fit() {
        let x = h, pts = ([x.tee, x.f, x.m, x.b] + x.hz.flatMap { [$0.p, $0.c] }).compactMap { $0 }
        if let t = x.tee, let g = x.m ?? x.f {
            let mid = GeoPoint(lat: (t.lat + g.lat) / 2, lng: (t.lng + g.lng) / 2)
            let len = Double(yards(t, g)) / 1.0936
            withAnimation { camera = .camera(MapCamera(centerCoordinate: mid.coordinate, distance: max(350, len * 2.6), heading: bearing(t, g), pitch: threeD ? 55 : 0)) }
        } else if let p = pts.first {
            withAnimation { camera = .camera(MapCamera(centerCoordinate: p.coordinate, distance: 600, heading: 0, pitch: threeD ? 55 : 0)) }
        } else if let any = doc.ev.map.holes.values.compactMap({ $0.m ?? $0.tee }).first {
            withAnimation { camera = .camera(MapCamera(centerCoordinate: any.coordinate, distance: 2500, heading: 0, pitch: 0)) }
        } else if let at = doc.ev.course.at {
            withAnimation { camera = .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: at.lat, longitude: at.lng), distance: 2500, heading: 0, pitch: 0)) }
        } else {
            search = doc.ev.course.name.components(separatedBy: " · ").first ?? doc.ev.club
            if search.count >= 3 { findPlace() }
        }
    }
    /// Find the course on the map with Apple Maps search.
    private func findPlace() {
        let r = MKLocalSearch.Request(); r.naturalLanguageQuery = search
        if #available(macOS 15.0, *) { r.pointOfInterestFilter = MKPointOfInterestFilter(including: [.golf]) }
        Task {
            var item = try? await MKLocalSearch(request: r).start().mapItems.first
            if item == nil { let r2 = MKLocalSearch.Request(); r2.naturalLanguageQuery = search; item = try? await MKLocalSearch(request: r2).start().mapItems.first }
            guard let c = item?.placemark.coordinate else { note = "Couldn’t find that. Try the town too."; return }
            note = nil
            withAnimation { camera = .camera(MapCamera(centerCoordinate: c, distance: 2500, heading: 0, pitch: 0)) }
        }
    }
    /// Map holes from OpenStreetMap: the empty ones, or every one.
    private func auto(all: Bool) {
        guard let region = lastRegion ?? currentRegion() else { note = "Find the course first, so it fills the map."; return }
        let s = region.center.latitude - region.span.latitudeDelta / 2, n = region.center.latitude + region.span.latitudeDelta / 2
        let w = region.center.longitude - region.span.longitudeDelta / 2, e = region.center.longitude + region.span.longitudeDelta / 2
        busy = true; note = "Looking for the course in OpenStreetMap…"
        Task {
            defer { busy = false }
            do {
                let pad = 0.004
                let els = try await OSM.fetch(south: s - pad, west: w - pad, north: n + pad, east: e + pad)
                let r = OSM.build(els, near: GeoPoint(lat: region.center.latitude, lng: region.center.longitude))
                if r.found.isEmpty {
                    note = r.unnumbered > 0 ? "OpenStreetMap has this course’s holes but not their numbers. Place them by hand." : "OpenStreetMap doesn’t have this course’s holes drawn. Place the tees and greens by hand: it takes a few minutes."
                    return
                }
                var added = 0
                for (k, v) in r.holes where all || doc.ev.map.holes[k]?.tee == nil {
                    doc.ev.map.holes[k] = v; added += 1
                }
                doc.ev.map.src = "osm"
                note = "Filled in \(added) hole\(added == 1 ? "" : "s") (\(r.found.map(String.init).joined(separator: ", "))). Check each one and drag anything that’s off."
                scheduleSave(); pick(firstOpenHole()); fit()
            } catch { note = error.localizedDescription }
        }
    }
    @State private var lastRegion: MKCoordinateRegion?
    private func currentRegion() -> MKCoordinateRegion? {
        if let c = camera.camera { return MKCoordinateRegion(center: c.centerCoordinate, latitudinalMeters: c.distance * 1.2, longitudinalMeters: c.distance * 1.6) }
        return nil
    }

    // ---- saving ----
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            if Task.isCancelled { return }
            saving = true; defer { saving = false }
            guard let map = try? Net.object(doc.ev.map) else { return }
            await doc.day("map", ["map": map])
        }
    }

    private func hazardColor(_ k: String) -> Color { ["bunker": Color(red: 0.95, green: 0.89, blue: 0.69), "water": .blue, "trees": .green, "layup": .white][k] ?? .orange }
}

extension GeoPoint { var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) } }
