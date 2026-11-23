import SwiftUI
import MapKit

/// The hole's yards on the scorecard (public/golf/gpscard.js): front, middle and back in big numbers, the hazards
/// ahead, and the course map. Yards are from the tee until GPS is on and you're on the hole.
struct GPSCard: View {
    var state: EventState
    var hole: Int
    var onHole: (Int) -> Void
    /// the cart's scorecard: the full-screen map then has the scores too
    var scorer: ScorecardModel? = nil
    @State private var loc = Locator.shared
    @State private var courseView = false

    var body: some View {
        let h = state.map.holes[hole]
        VStack(alignment: .leading, spacing: 12) {
            if let h, Geo.middle(h) != nil {
                let me = loc.fix?.at
                let o = Geo.origin(h, me)
                let y = o.map { Geo.yardages(h, from: $0.at) }
                HStack(spacing: 6) {
                    yard("Front", y?.f, big: false)
                    yard(o?.me == true ? "To the middle" : "Middle, from tee", y?.m, big: true)
                    yard("Back", y?.b, big: false)
                }
                if let hz = y?.hz, !hz.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(hz.prefix(6)) { z in
                            (Text(z.name + " ") + Text("\(z.reach)").bold().monospacedDigit() + Text(z.carry.map { "–\($0)" } ?? "").bold().monospacedDigit())
                                .font(.caption).padding(.horizontal, 9).padding(.vertical, 5)
                                .background(Color.fcPaper2, in: Capsule())
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
                .font(.footnote).foregroundStyle(Color.fcMuted)
                HStack(spacing: 8) {
                    Button { courseView = true } label: { Label(scorer == nil ? "Course map" : "Full screen GPS", systemImage: "arrow.up.left.and.arrow.down.right") }
                        .buttonStyle(.fc(.dark, full: true))
                    if !loc.on {
                        Button { loc.start() } label: { Label("Use my GPS", systemImage: "location.fill") }
                            .buttonStyle(.fc(.plain, full: true))
                    }
                }
            } else {
                Text("Hole \(hole) isn’t on the course map yet.").font(.footnote).foregroundStyle(Color.fcMuted)
            }
        }
        .foregroundStyle(Color.fcInk)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fcCard(padding: 14)
        .fullScreenCover(isPresented: $courseView) {
            CourseView(state: state, hole: hole, onHole: onHole, scorer: scorer)
        }
    }

    private func yard(_ label: String, _ v: Int?, big: Bool) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.caption2.weight(.semibold)).tracking(0.8).textCase(.uppercase).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(big ? Color.fcFlag : Color.fcMuted)
            Text(v.map(String.init) ?? "—").font(FCType.display(big ? 50 : 32)).monospacedDigit()
                .foregroundStyle(big ? Color.white : Color.fcInk)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity).padding(.vertical, big ? 8 : 4)
        .background(big ? Color(UIColor(hex: 0x123628)) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Full-screen satellite view of the hole, turned so where you hit from is at the bottom and the green at the
/// top, with carry arcs every 50 yards, hazards with reach / carry, the flag, and tap-to-measure.
struct CourseView: View {
    var state: EventState
    @State var hole: Int
    var onHole: (Int) -> Void
    /// in the Course tab: no close button, and the yards in a big panel at the bottom
    var embedded = false
    /// the cart's scorecard: score each player without leaving the map
    var scorer: ScorecardModel? = nil
    @State private var scoresOpen = true
    @State private var fullScreen = false
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
    @State private var titleCard = false   // the hole's name card during a flight

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
        .overlay(alignment: .topTrailing) { if !bigYards { yardageBox.padding(.top, 76).padding(.trailing, 12).opacity(flying ? 0 : 1) } }
        .overlay(alignment: .bottomLeading) { flyButton.padding(.leading, 12).padding(.bottom, 12) }
        .overlay(alignment: .bottomLeading) { holeCard.padding(.leading, 18).padding(.bottom, 66) }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if bigYards { yardPanel }
                if let scorer { scorePanel(scorer) } else { footer }
            }
        }
        .modifier(DarkScheme(local: embedded))
        // follow the scorecard when its hole changes elsewhere
        .onChange(of: scorer?.currentHole()) { _, n in if let n, n != hole { hole = n } }
        .fullScreenCover(isPresented: $fullScreen) {
            CourseView(state: state, hole: hole, onHole: onHole, scorer: scorer)
        }
        .onAppear { if loc.on { loc.resume() } }
    }

    @MapContentBuilder
    private func content(_ h: HoleMap, _ g: GeoPoint) -> some MapContent {
        let from = origin?.at
        if let from, let toG = Geo.yds(from, g) {
            // the hole from here to the green, round its doglegs
            let way = FlyPath.ahead(h, from: from, green: g)
            // carry arcs every 50 yards from where you are, each centred where it crosses the fairway
            ForEach(Array(stride(from: 50.0, to: toG - 25, by: 50.0)).filter { !($0 < 100 && toG > 250) }, id: \.self) { d in
                let up = FlyPath.cross(way, from: from, yards: d).map { Geo.bearing(from, $0) } ?? Geo.bearing(from, g)
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
                MapPolyline(coordinates: way.map(\.coordinate)).stroke(.white.opacity(0.95), lineWidth: 2.5)
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

    /// "Fly the hole", like a drone flyover on TV: it drops to the tee box, pushes off low down the hole as it's
    /// played (round its doglegs, from the course map's line), eases to a stop short of the green looking at it, then
    /// pulls back to the whole hole. The camera path is FlyPath, the same one the Mac Manager's course map flies.
    private func flightPlan(_ h: HoleMap, _ g: GeoPoint) -> FlyPath {
        FlyPath.make(h, tee: h.tee ?? origin?.at ?? g, green: g)
    }
    static let flyIn = 1.2, flyOut = 2.0     // seconds: dropping to the tee, pulling back at the end

    /// the flight as frames every 0.1 s along the path (FlyPath.camera), headings turning the short way
    private func flightFrames(_ h: HoleMap, _ g: GeoPoint) -> (frames: [(GeoPoint, Double, Double, Double)], end: MapCamera) {
        let p = flightPlan(h, g), end = view3D(from: h.tee ?? origin?.at ?? g, to: g)
        var out: [(GeoPoint, Double, Double, Double)] = []
        var last = p.camera(at: 0).heading, t = 0.0
        while t <= p.totalSecs + 0.001 {
            let c = p.camera(at: t)
            var hd = c.heading
            while hd - last > 180 { hd -= 360 }
            while hd - last < -180 { hd += 360 }
            last = hd; out.append((c.at, hd, c.metres, c.pitch)); t += 0.1
        }
        var e = end.heading
        while e - last > 180 { e -= 360 }
        while e - last < -180 { e += 360 }
        var endCam = end; endCam.heading = e
        return (out, endCam)
    }

    @KeyframesBuilder<MapCamera>
    private func flight(_ h: HoleMap, _ g: GeoPoint) -> some Keyframes<MapCamera> {
        let f = flightFrames(h, g)
        KeyframeTrack(\MapCamera.centerCoordinate) {
            CubicKeyframe(f.frames[0].0.coordinate, duration: Self.flyIn)
            for fr in f.frames.dropFirst() { LinearKeyframe(fr.0.coordinate, duration: 0.1) }
            CubicKeyframe(f.end.centerCoordinate, duration: Self.flyOut)
        }
        KeyframeTrack(\MapCamera.heading) {
            CubicKeyframe(f.frames[0].1, duration: Self.flyIn)
            for fr in f.frames.dropFirst() { LinearKeyframe(fr.1, duration: 0.1) }
            CubicKeyframe(f.end.heading, duration: Self.flyOut)
        }
        KeyframeTrack(\MapCamera.distance) {
            CubicKeyframe(f.frames[0].2, duration: Self.flyIn)
            for fr in f.frames.dropFirst() { LinearKeyframe(fr.2, duration: 0.1) }
            CubicKeyframe(f.end.distance, duration: Self.flyOut)
        }
        KeyframeTrack(\MapCamera.pitch) {
            CubicKeyframe(f.frames[0].3, duration: Self.flyIn)
            for fr in f.frames.dropFirst() { LinearKeyframe(fr.3, duration: 0.1) }
            CubicKeyframe(f.end.pitch, duration: Self.flyOut)
        }
    }

    @ViewBuilder private var flyButton: some View {
        if threeD, let h, let g = Geo.middle(h) {
            Button {
                flying = true; fly += 1
                let secs = flightPlan(h, g).totalSecs
                // the hole's name card, as the camera pushes off the tee
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.flyIn + 0.5) { withAnimation(.easeOut(duration: 0.6)) { titleCard = true } }
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.flyIn + 6) { withAnimation(.easeIn(duration: 0.6)) { titleCard = false } }
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.flyIn + secs + Self.flyOut + 0.2) {
                    flying = false; titleCard = false
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

    /// "Hole 6 / 402 Yards / Par 4", bottom left, while the camera leaves the tee
    @ViewBuilder private var holeCard: some View {
        if titleCard, hole >= 1, hole <= state.course.holes.count {
            let H = state.course.holes[hole - 1]
            let yds = H.yds > 0 ? H.yds : h.flatMap { m in Geo.middle(m).map { g in Int(FlyPath.length(FlyPath.holePath(m, tee: m.tee ?? g, green: g)).rounded()) } } ?? 0
            VStack(alignment: .leading, spacing: 1) {
                Text("Hole \(hole)").font(.system(size: 30, weight: .bold, design: .serif))
                if yds > 0 { Text("\(yds) Yards").font(.system(size: 14, weight: .semibold, design: .serif)) }
                Text("Par \(H.par)").font(.system(size: 14, weight: .semibold, design: .serif))
            }
            .italic().foregroundStyle(.white).shadow(color: .black.opacity(0.55), radius: 6, y: 1)
            .transition(.opacity.combined(with: .offset(x: -12)))
            .allowsHitTesting(false)
        }
    }

    private var topBar: some View {
        let H = state.course.holes[hole - 1]
        return HStack(spacing: 10) {
            if !embedded {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 40, height: 40).background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8)) }
                    .accessibilityLabel("Close")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Hole \(hole)").font(FCType.display(30)).textCase(.uppercase)
                Text("Par \(H.par)\(H.yds > 0 ? " · \(H.yds) yds" : "")").font(.caption.monospaced()).foregroundStyle(Color(UIColor(hex: 0xa9bdb0)))
            }
            Spacer()
            if embedded {
                Button { fullScreen = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.headline).frame(width: 40, height: 40)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityLabel("Full screen")
            }
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

    private var bigYards: Bool { embedded || scorer != nil }

    /// Scores on the map: each player's score for this hole with − and +, tap the number for par.
    /// Folds down to one line to show more of the hole.
    private func scorePanel(_ m: ScorecardModel) -> some View {
        let H = state.course.holes[hole - 1]
        let ps = m.team.map { state.scorers($0) } ?? []
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button { withAnimation(.snappy) { scoresOpen.toggle() } } label: {
                    HStack(spacing: 6) {
                        Text("Scores · hole \(hole)").font(.subheadline.weight(.bold))
                        Image(systemName: scoresOpen ? "chevron.down" : "chevron.up").font(.caption.weight(.bold))
                    }
                    .frame(minHeight: 36).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if !scoresOpen {
                    Text(ps.map { p in "\(Fmt.firstName(p.name)) \(m.value(p.id, hole).map { $0 == 0 ? "PU" : "\($0)" } ?? "–")" }.joined(separator: " · "))
                        .font(.subheadline.monospacedDigit()).foregroundStyle(Color(UIColor(hex: 0xcfdcd3))).lineLimit(1)
                }
                Spacer(minLength: 4)
                if !loc.on {
                    Button("Use my GPS") { loc.start() }.font(.subheadline.weight(.bold))
                        .padding(.horizontal, 12).frame(minHeight: 36).background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            if scoresOpen {
                ForEach(ps) { p in
                    let v = m.value(p.id, hole), set = v != nil
                    let mark = Core.mark(v, H.par)
                    HStack(spacing: 10) {
                        Text(Fmt.firstName(p.name)).font(.headline).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        mapStep("minus", "One fewer for \(p.name)") { score(m, p.id, -1) }
                        Button { score(m, p.id, 0) } label: {
                            Text(!set ? "\(H.par)" : v == 0 ? "PU" : "\(v!)")
                                .font(FCType.display(34)).frame(width: 54, height: 46)
                                .foregroundStyle(!set ? Color.white.opacity(0.45) : mark == .birdie || mark == .eagle ? Color(UIColor(hex: 0xff8a80)) : .white)
                                .background(set ? Color.white.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 12))
                                .overlay { if !set { RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])) } }
                                .contentTransition(.numericText())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(set ? "\(p.name) score \(v == 0 ? "picked up" : "\(v!)")" : "Tap to enter par for \(p.name)")
                        mapStep("plus", "One more for \(p.name)") { score(m, p.id, 1) }
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(UIColor(hex: 0x0b1a12)).opacity(0.94))
        .sensoryFeedback(.selection, trigger: m.changes)
        .animation(.snappy(duration: 0.2), value: m.changes)
    }
    /// scores go on the hole the map shows
    private func score(_ m: ScorecardModel, _ p: String, _ d: Int) {
        if m.currentHole() != hole { m.hole = hole }
        m.step(p, d)
    }
    private func mapStep(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title3.weight(.bold)).frame(width: 46, height: 46)
                .background(.white.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Course tab: front, middle and back in big numbers, the middle on a green tile
    @ViewBuilder private var yardPanel: some View {
        if let h, let o = origin {
            let y = Geo.yardages(h, from: o.at)
            HStack(spacing: 8) {
                yard("Front", y.f, big: false)
                yard(o.me ? "Middle" : "Middle, from the tee", y.m, big: true)
                yard("Back", y.b, big: false)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
            .background(Color(UIColor(hex: 0x0b1a12)).opacity(0.92))
            .opacity(flying ? 0 : 1)
            .allowsHitTesting(false)
        }
    }
    private func yard(_ label: String, _ v: Int?, big: Bool) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.caption2.weight(.semibold)).tracking(1).textCase(.uppercase).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(big ? Color(UIColor(hex: 0xf2d04f)) : Color(UIColor(hex: 0xa9bdb0)))
            Text(v.map(String.init) ?? "—").font(FCType.display(big ? 52 : 34)).monospacedDigit().foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity).padding(.vertical, big ? 8 : 4)
        .background(big ? Color(UIColor(hex: 0x123628)) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
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

/// Full screen (a cover) sets the whole presentation dark; inside a tab only this view goes dark.
private struct DarkScheme: ViewModifier {
    var local: Bool
    func body(content: Content) -> some View {
        if local { content.environment(\.colorScheme, .dark) } else { content.preferredColorScheme(.dark) }
    }
}
