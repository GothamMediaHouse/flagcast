import SwiftUI
import MapKit

/// The hole GPS card on the scorecard (public/golf/gpscard.js): middle in big numbers, front and back,
/// the hazards ahead, and Course view. Yards are from the tee until GPS is on and you're on the hole.
struct GPSCard: View {
    var state: EventState
    var hole: Int
    var onHole: (Int) -> Void
    @State private var loc = Locator.shared
    @State private var courseView = false

    var body: some View {
        let h = state.map.holes[hole]
        VStack(alignment: .leading, spacing: 10) {
            if let h, Geo.middle(h) != nil {
                let me = loc.fix?.at
                let o = Geo.origin(h, me)
                let y = o.map { Geo.yardages(h, from: $0.at) }
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(y?.m.map(String.init) ?? "—")
                            .font(FCType.display(46)).monospacedDigit()
                            .contentTransition(.numericText())
                        Text(o?.me == true ? "to the middle" : "middle, from the tee").fcLabel().foregroundStyle(Color.fcOnGreenMuted)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        if let f = y?.f { (Text("Front ").foregroundStyle(Color.fcOnGreenMuted) + Text("\(f)").bold()) }
                        if let b = y?.b { (Text("Back ").foregroundStyle(Color.fcOnGreenMuted) + Text("\(b)").bold()) }
                    }
                    .font(.subheadline.monospaced())
                    Spacer(minLength: 4)
                    VStack(spacing: 6) {
                        Button { courseView = true } label: { Text("Course view").lineLimit(1).fixedSize() }
                            .font(.subheadline.weight(.bold)).padding(.horizontal, 12).frame(minHeight: 38)
                            .background(Color.fcFlag, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(Color.fcOnFlag)
                        if !loc.on {
                            Button { loc.start() } label: { Text("Use my GPS").lineLimit(1).fixedSize() }
                                .font(.subheadline.weight(.bold)).padding(.horizontal, 12).frame(minHeight: 38)
                                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .buttonStyle(.plain)
                }
                if let hz = y?.hz, !hz.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(hz.prefix(6)) { z in
                            (Text(z.name + " ") + Text("\(z.reach)").bold().monospacedDigit() + Text(z.carry.map { "–\($0)" } ?? "").bold().monospacedDigit())
                                .font(.caption).padding(.horizontal, 9).padding(.vertical, 4)
                                .background(Color.white.opacity(0.1), in: Capsule())
                        }
                    }
                }
                Group {
                    if let e = loc.error { Text(e) }
                    else if !loc.on { Text("Yards from the tee. Turn on GPS for yards from where you are\(Geo.trackingOn(state) ? " (during the tournament the desk sees where your group is)" : "").") }
                    else if loc.fix == nil { Text("Finding your spot…") }
                    else if o?.me != true { Text("You’re not on hole \(hole) yet, so these are from the tee.") }
                    else {
                        HStack(spacing: 4) {
                            Text("GPS to within \(loc.fix!.acc) yds.\(Geo.trackingOn(state) ? " The desk can see where your group is until the results are final." : "")")
                            Button("Turn off") { loc.stop() }.underline().buttonStyle(.plain)
                        }
                    }
                }
                .font(.footnote).foregroundStyle(Color.fcOnGreenMuted)
            } else {
                Text("Hole \(hole) isn’t on the course map yet.").font(.footnote).foregroundStyle(Color.fcOnGreenMuted)
            }
        }
        .foregroundStyle(Color.fcOnGreen)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fcGreen, in: RoundedRectangle(cornerRadius: 12))
        .fullScreenCover(isPresented: $courseView) {
            CourseView(state: state, hole: hole, onHole: onHole)
        }
    }
}

/// Full-screen satellite view of the hole, turned so where you hit from is at the bottom and the green at the
/// top, with carry arcs every 50 yards, hazards with reach / carry, the flag, and tap-to-measure.
struct CourseView: View {
    var state: EventState
    @State var hole: Int
    var onHole: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var loc = Locator.shared
    @State private var camera: MapCameraPosition = .automatic
    @State private var tap: GeoPoint?
    @State private var framedFor = ""
    /// 3D: Apple's elevation imagery seen from behind where you hit from (remembered). Flat satellite where
    /// Apple has no 3D data for the course.
    @AppStorage("flagcast.course3d") private var threeD = false
    @State private var fly = 0          // bumps to run "Fly the hole"
    @State private var flying = false

    private var h: HoleMap? { state.map.holes[hole] }
    private var origin: (at: GeoPoint, me: Bool)? { h.flatMap { Geo.origin($0, loc.fix?.at) } }

    var body: some View {
        ZStack(alignment: .top) {
            if let h, let g = Geo.middle(h) {
                MapReader { proxy in
                    Map(position: $camera, interactionModes: threeD ? [.zoom, .pan, .pitch, .rotate] : [.zoom, .pan]) {
                        content(h, g)
                    }
                    .mapStyle(.imagery(elevation: threeD ? .realistic : .flat))
                    .mapControlVisibility(.hidden)
                    .mapCameraKeyframeAnimator(trigger: fly) { _ in flight(h, g) }
                    .onTapGesture { pt in
                        guard let c = proxy.convert(pt, from: .local) else { return }
                        let p = GeoPoint(c)
                        if let t = tap, let d = Geo.yds(t, p), d < 8 { tap = nil } else { tap = p }
                    }
                }
                .ignoresSafeArea()
                .onAppear {
                    frame(h, g)
                    if threeD { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { if let h = self.h, let g = Geo.middle(h) { frame(h, g) } } }
                }
                .onChange(of: hole) { _, _ in tap = nil; if let h = self.h, let g = Geo.middle(h) { frame(h, g) } }
                .onChange(of: origin?.me) { _, _ in frame(h, g) }
                .onChange(of: threeD) { _, _ in
                    // let the map switch styles first, or the tilt is dropped
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { if let h = self.h, let g = Geo.middle(h) { frame(h, g) } }
                }
            } else {
                Color(UIColor(hex: 0x0b1a12)).ignoresSafeArea()
                Text("Hole \(hole) isn’t on the course map yet.").foregroundStyle(.white).padding(.top, 200)
            }
            topBar
        }
        .overlay(alignment: .topTrailing) { yardageBox.padding(.top, 76).padding(.trailing, 12) }
        .overlay(alignment: .bottomLeading) { flyButton.padding(.leading, 12).padding(.bottom, 12) }
        .safeAreaInset(edge: .bottom) { footer }
        .preferredColorScheme(.dark)
        .onAppear { if loc.on { loc.resume() } }
    }

    @MapContentBuilder
    private func content(_ h: HoleMap, _ g: GeoPoint) -> some MapContent {
        let from = origin?.at
        if let from, let toG = Geo.yds(from, g) {
            let up = Geo.bearing(from, g)
            // carry arcs every 50 yards from where you are
            ForEach(Array(stride(from: 50.0, to: toG - 25, by: 50.0)).filter { !($0 < 100 && toG > 250) }, id: \.self) { d in
                let span = min(28.0, 70.0 / max(d, 1) * 57.3 * 0.9)
                MapPolyline(coordinates: stride(from: -span, through: span, by: span / 8).map { Geo.offset(from, yards: d, bearing: up + $0).coordinate })
                    .stroke(.white.opacity(0.55), lineWidth: 1.5)
                Annotation("", coordinate: Geo.offset(from, yards: d, bearing: up + span + 3).coordinate) {
                    Text("\(Int(d))").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.9)).shadow(radius: 2)
                }
            }
            if let t = tap {
                MapPolyline(coordinates: [from.coordinate, t.coordinate, g.coordinate]).stroke(Color(UIColor(hex: 0xf2d04f)), lineWidth: 3)
                Annotation("", coordinate: t.coordinate) { Circle().fill(Color(UIColor(hex: 0xf2d04f))).frame(width: 16, height: 16).overlay(Circle().stroke(.black, lineWidth: 1.5)) }
                Annotation("", coordinate: mid(from, t).coordinate) { pill("\(Int(jsRound(Geo.yds(from, t) ?? 0)))", gold: true) }
                Annotation("", coordinate: mid(t, g).coordinate) { pill("\(Int(jsRound(Geo.yds(t, g) ?? 0)))", gold: true) }
            } else {
                MapPolyline(coordinates: [from.coordinate, g.coordinate]).stroke(.white.opacity(0.95), lineWidth: 2.5)
            }
            if origin?.me == false, let tee = h.tee {
                Annotation("", coordinate: tee.coordinate) {
                    Text("T").font(.caption2.weight(.heavy)).foregroundStyle(Color.fcOnFlag).frame(width: 18, height: 18)
                        .background(Color(UIColor(hex: 0xf2d04f)), in: Circle()).overlay(Circle().stroke(.black.opacity(0.8), lineWidth: 1.5))
                }
            }
        }
        // hazards: where you reach it, a line to where it's carried, and the numbers
        ForEach(h.hz) { z in
            let color = hazardColor(z.k)
            if let c = z.c { MapPolyline(coordinates: [z.p.coordinate, c.coordinate]).stroke(color, lineWidth: 2.5) }
            Annotation("", coordinate: z.p.coordinate) {
                HStack(spacing: 4) {
                    Circle().fill(color).frame(width: 9, height: 9).overlay(Circle().stroke(.black.opacity(0.55), lineWidth: 1))
                    if let from {
                        let r = Int(jsRound(Geo.yds(from, z.p) ?? 0)), c = z.c.map { Int(jsRound(Geo.yds(from, $0) ?? 0)) }
                        pill("\(r)\(c.map { " · \($0)" } ?? "")", dot: color)
                    }
                }
            }
        }
        // the green: front and back marks, and the flag
        ForEach([h.f, h.b].compactMap { $0 }, id: \.self) { p in
            Annotation("", coordinate: p.coordinate) { Circle().fill(.white.opacity(0.9)).frame(width: 7, height: 7).overlay(Circle().stroke(.black.opacity(0.4), lineWidth: 1)) }
        }
        Annotation("", coordinate: g.coordinate, anchor: .bottomLeading) {
            Image(systemName: "flag.fill").font(.title2).foregroundStyle(Color(UIColor(hex: 0xe0362c))).shadow(radius: 3)
                .offset(x: -3)
        }
        if let me = loc.fix?.at {
            Annotation("", coordinate: me.coordinate) {
                Circle().fill(Color(UIColor(hex: 0x2f7bff))).frame(width: 15, height: 15)
                    .overlay(Circle().stroke(.white, lineWidth: 3)).background(Circle().fill(Color.blue.opacity(0.22)).frame(width: 32, height: 32))
            }
        }
    }

    private func mid(_ a: GeoPoint, _ b: GeoPoint) -> GeoPoint { GeoPoint(lat: (a.lat + b.lat) / 2, lng: (a.lng + b.lng) / 2) }

    private func hazardColor(_ k: String) -> Color {
        Color(UIColor(hex: ["bunker": 0xf2e2b0, "water": 0x5fb4ff, "trees": 0x7fd18b, "layup": 0xffffff][k] ?? 0xffb36b))
    }

    private func pill(_ t: String, gold: Bool = false, dot: Color? = nil) -> some View {
        Text(t).font(.system(size: gold ? 15 : 13, weight: .bold)).monospacedDigit()
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(gold ? Color(UIColor(hex: 0xf2d04f)) : Color(red: 12 / 255, green: 22 / 255, blue: 16 / 255).opacity(0.88), in: Capsule())
            .foregroundStyle(gold ? Color.fcOnFlag : .white)
            .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
    }

    /// Bottom = where you hit from, top = the green, zoomed so the hole fits (never closer than ~70 yards).
    private func frame(_ h: HoleMap, _ g: GeoPoint) {
        let o = origin
        let a = o?.at ?? g
        let len = max(70, Geo.yds(a, g) ?? 70)
        // a little past halfway toward the green, so the green sits clear of the top bar and the yardage box
        let center = GeoPoint(lat: a.lat + (g.lat - a.lat) * 0.56, lng: a.lng + (g.lng - a.lng) * 0.56)
        let heading = o == nil ? 0 : Geo.bearing(a, g)
        // distance (metres) the camera sits above: enough to fit the hole in about 60% of the screen height
        let metres = len / Geo.YD * 3.8
        withAnimation(.easeInOut(duration: threeD ? 0.8 : 0.4)) {
            camera = .camera(threeD ? view3D(from: a, to: g, heading: o == nil ? 0 : nil)
                                    : MapCamera(centerCoordinate: center.coordinate, distance: metres, heading: heading, pitch: 0))
        }
    }

    static let pitch3D = 56.0

    /// The 3D view of a hole: tilted about 56°, looking along the line to the green from behind and above where
    /// you hit from, far enough back that the whole hole (where you are to the green) is on screen.
    private func view3D(from a: GeoPoint, to g: GeoPoint, heading: Double? = nil) -> MapCamera {
        let len = max(60, Geo.yds(a, g) ?? 60), up = heading ?? Geo.bearing(a, g)
        let look = Geo.offset(a, yards: len * 0.47, bearing: up)
        // tuned on the simulator: this puts where you are near the bottom and the green below the top bar
        let metres = (len * 0.54 + 60) / Geo.YD / sin(Self.pitch3D * .pi / 180) * 2.15
        return MapCamera(centerCoordinate: look.coordinate, distance: metres, heading: up, pitch: Self.pitch3D)
    }

    /// "Fly the hole": from behind the tee down the line to just short of the green (about 6 s), then it settles
    /// on the green.
    private func flightPlan(_ h: HoleMap, _ g: GeoPoint) -> (start: GeoPoint, short: GeoPoint, up: Double, end: MapCamera) {
        let tee = h.tee ?? origin?.at ?? g
        let up = Geo.bearing(tee, g), len = max(60, Geo.yds(tee, g) ?? 60)
        let ahead = Self.flyLow * sin(60 * .pi / 180) * Geo.YD     // yards from the camera to the point it looks at
        return (Geo.offset(tee, yards: ahead - 30, bearing: up),          // camera about 30 yds behind the tee
                Geo.offset(tee, yards: max(ahead, len - 25), bearing: up),
                up, view3D(from: tee, to: g))
    }
    static let flyLow = 260.0, flySettle = 210.0   // metres from the camera to the point it looks at

    @KeyframesBuilder<MapCamera>
    private func flight(_ h: HoleMap, _ g: GeoPoint) -> some Keyframes<MapCamera> {
        let p = flightPlan(h, g)
        KeyframeTrack(\MapCamera.centerCoordinate) {
            CubicKeyframe(p.start.coordinate, duration: 0.6)
            CubicKeyframe(p.short.coordinate, duration: 6)
            CubicKeyframe(g.coordinate, duration: 1.8)
            CubicKeyframe(p.end.centerCoordinate, duration: 1.2)
        }
        KeyframeTrack(\MapCamera.distance) {
            CubicKeyframe(Self.flyLow, duration: 0.6)
            LinearKeyframe(Self.flyLow, duration: 6)
            CubicKeyframe(Self.flySettle, duration: 1.8)
            CubicKeyframe(p.end.distance, duration: 1.2)
        }
        KeyframeTrack(\MapCamera.pitch) {
            CubicKeyframe(60, duration: 0.6)
            LinearKeyframe(60, duration: 6)
            CubicKeyframe(45, duration: 1.8)
            CubicKeyframe(Self.pitch3D, duration: 1.2)
        }
        KeyframeTrack(\MapCamera.heading) {
            CubicKeyframe(p.up, duration: 0.6)
            LinearKeyframe(p.up, duration: 9)
        }
    }

    @ViewBuilder private var flyButton: some View {
        if threeD, let h, Geo.middle(h) != nil {
            Button {
                flying = true; fly += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 9.8) {
                    flying = false
                    if let h = self.h, let g = Geo.middle(h) { camera = .camera(view3D(from: h.tee ?? origin?.at ?? g, to: g)); frame(h, g) }
                }
            } label: {
                Label(flying ? "Flying…" : "Fly the hole", systemImage: "airplane").font(.subheadline.weight(.bold))
                    .padding(.horizontal, 14).frame(minHeight: 40)
                    .background(Color(UIColor(hex: 0xf2d04f)), in: Capsule()).foregroundStyle(Color.fcOnFlag)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
            }
            .disabled(flying)
        }
    }

    private var topBar: some View {
        let H = state.course.holes[hole - 1]
        return HStack(spacing: 10) {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 40, height: 40).background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8)) }
                .accessibilityLabel("Close")
            VStack(alignment: .leading, spacing: 2) {
                Text("Hole \(hole)").font(FCType.display(30)).textCase(.uppercase)
                Text("Par \(H.par)\(H.yds > 0 ? " · \(H.yds) yds" : "")").font(.caption.monospaced()).foregroundStyle(Color(UIColor(hex: 0xa9bdb0)))
            }
            Spacer()
            Button { threeD.toggle() } label: {
                Text("3D").font(.subheadline.weight(.heavy)).frame(width: 44, height: 40)
                    .background(threeD ? Color(UIColor(hex: 0xf2d04f)) : .white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(threeD ? Color.fcOnFlag : .white)
            }
            .accessibilityLabel(threeD ? "3D view on" : "3D view off")
            Button { step(-1) } label: { Image(systemName: "chevron.left").font(.headline).frame(width: 40, height: 40).background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8)) }
                .accessibilityLabel("Previous hole")
            Button { step(1) } label: { Image(systemName: "chevron.right").font(.headline).frame(width: 40, height: 40).background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8)) }
                .accessibilityLabel("Next hole")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(UIColor(hex: 0x0b1a12)).opacity(0.92))
    }

    private func step(_ d: Int) {
        let ph = Core.playHoles(state), i = ph.firstIndex(of: hole) ?? 0
        hole = ph[(i + d + ph.count) % ph.count]
        onHole(d)
    }

    @ViewBuilder private var yardageBox: some View {
        if let h, let o = origin {
            let y = Geo.yardages(h, from: o.at)
            VStack(alignment: .trailing, spacing: 2) {
                Text(y.m.map(String.init) ?? "—").font(FCType.display(40)).foregroundStyle(.white).monospacedDigit()
                Text(o.me ? "to the middle" : "from the tee")
                if y.f != nil || y.b != nil {
                    Text([y.f.map { "Front \($0)" }, y.b.map { "Back \($0)" }].compactMap { $0 }.joined(separator: " · "))
                }
            }
            .font(.caption.monospaced()).foregroundStyle(Color(UIColor(hex: 0xa9bdb0)))
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color(UIColor(hex: 0x0b1a12)).opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
            .allowsHitTesting(false)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Group {
                if let t = tap, let o = origin, let g = h.flatMap(Geo.middle) {
                    Text("\(Int(jsRound(Geo.yds(o.at, t) ?? 0))) yds there, then \(Int(jsRound(Geo.yds(t, g) ?? 0))) to the middle. Tap it again to clear.")
                } else if threeD {
                    Text("3D: tap to measure, two fingers to tilt or turn. Where Apple has no 3D for a course you see a tilted satellite view.")
                } else {
                    Text("Tap anywhere to measure: how far there, and what’s left to the green.")
                }
            }
            .font(.subheadline).foregroundStyle(Color(UIColor(hex: 0xcfdcd3)))
            Spacer(minLength: 4)
            if !loc.on {
                Button("Use my GPS") { loc.start() }.font(.subheadline.weight(.bold))
                    .padding(.horizontal, 12).frame(minHeight: 38).background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(UIColor(hex: 0x0b1a12)).opacity(0.92))
        .overlay(alignment: .topTrailing) {
            Text(state.map.src == "osm" ? "Course data © OpenStreetMap" : "").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).padding(.trailing, 8).offset(y: -16)
        }
    }
}
