import SwiftUI

/// Pin sheet (the web desk's Pin sheet, public/golf/desk): where the pin is on each green today. Every change saves
/// at once (day op "pinsheet") and golfers see the flag and their yards to the pin straight away.
/// Shared by the Mac Manager (PinsView) and the iPhone and iPad Manager.
struct PinBoard: View {
    let doc: DeskDoc
    /// tiles per row in the hole grid
    var columns = 6
    /// the editor under the grid (iPhone) instead of beside it
    var stacked = false
    @State private var hole = 1
    /// changes on their way to the server, shown at once (the live feed catches up a moment later)
    @State private var pending: [Int: PinSpot?] = [:]
    @State private var saving: Task<Void, Never>?

    private var holes: [Hole] { doc.ev.course.holes.filter { doc.ev.playHoles.contains($0.n) } }
    private func pin(_ n: Int) -> PinSpot? { if let p = pending[n] { return p }; return doc.live?.pinsheet[n] }

    var body: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 14) { toolbar; editor; grid }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    toolbar
                    HStack(alignment: .top, spacing: 16) { grid; editor.frame(width: 300) }
                }
            }
        }
        .onAppear { if !holes.contains(where: { $0.n == hole }) { hole = holes.first?.n ?? 1 } }
        .onChange(of: doc.live?.pinsheet) { _, live in
            // the feed has what we sent: stop overriding it
            let have = live ?? [:]
            for (n, p) in pending where have[n] == p { pending[n] = nil }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            let set = holes.filter { pin($0.n) != nil }.count
            Text("\(set) of \(holes.count) holes set").font(.callout).foregroundStyle(FC.muted)
            Spacer()
            if set > 0 {
                Button(role: .destructive) { Task { await clearAll() } } label: { Label("Clear all pins", systemImage: "trash") }
                    .buttonStyle(.borderless)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(holes, id: \.n) { h in
                let p = pin(h.n), on = h.n == hole
                Button { hole = h.n } label: {
                    VStack(spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(h.n)").font(FC.display(20)).foregroundStyle(FC.green)
                            Spacer()
                            Text("Par \(h.par)").font(.caption2).foregroundStyle(FC.muted)
                        }
                        PinGreen(pin: p, big: false).frame(width: 54, height: 50)
                        Text(p?.label ?? "Not set").font(.caption.weight(p == nil ? .regular : .semibold))
                            .foregroundStyle(p == nil ? FC.muted : FC.ink).lineLimit(1).minimumScaleFactor(0.8)
                        Text(p?.paces ?? " ").font(.caption2).foregroundStyle(FC.muted).lineLimit(1)
                    }
                    .padding(8)
                    .background(FC.card, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? FC.green : FC.line, lineWidth: on ? 2 : 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hole \(h.n), \(p?.label ?? "pin not set")")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private var editor: some View {
        if let h = holes.first(where: { $0.n == hole }) ?? holes.first {
            let p = pin(h.n), i = holes.firstIndex(of: h) ?? 0
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Hole \(h.n)").font(FC.display(26))
                        Text("Par \(h.par)\(h.yds > 0 ? " · \(h.yds) yds" : "")").font(.caption).foregroundStyle(FC.muted)
                    }
                    Spacer()
                    Button { hole = holes[i - 1].n } label: { Image(systemName: "chevron.left") }.disabled(i == 0).accessibilityLabel("Hole before")
                    Button { hole = holes[i + 1].n } label: { Image(systemName: "chevron.right") }.disabled(i >= holes.count - 1).accessibilityLabel("Next hole")
                }
                Text("BACK").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(FC.muted).frame(maxWidth: .infinity)
                GeometryReader { g in
                    PinGreen(pin: p, big: true)
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { t in
                            let x = t.location.x / g.size.width * 150, y = t.location.y / g.size.height * 140
                            var n = p ?? PinSpot()
                            n.d = y < 49 ? "B" : y < 88 ? "M" : "F"; n.s = x < 62 ? "L" : x < 98 ? "C" : "R"
                            set(h.n, n)
                        })
                }
                .aspectRatio(150 / 140, contentMode: .fit)
                .frame(maxWidth: 250).frame(maxWidth: .infinity)
                .accessibilityLabel("The green. Tap where the pin is.")
                Text("FRONT (from the fairway)").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(FC.muted).frame(maxWidth: .infinity)
                Picker("Depth", selection: Binding(get: { p?.d ?? "" }, set: { var n = p ?? PinSpot(); n.d = $0; set(h.n, n) })) {
                    Text("Front").tag("F"); Text("Middle").tag("M"); Text("Back").tag("B")
                }
                .pickerStyle(.segmented).labelsHidden()
                Picker("Side", selection: Binding(get: { p?.s ?? "" }, set: { var n = p ?? PinSpot(); n.s = $0; set(h.n, n) })) {
                    Text("Left").tag("L"); Text("Center").tag("C"); Text("Right").tag("R")
                }
                .pickerStyle(.segmented).labelsHidden()
                Stepper(value: Binding(get: { p?.on ?? 0 }, set: { var n = p ?? PinSpot(); n.on = max(0, min(60, $0)); set(h.n, n, wait: true) }), in: 0...60) {
                    HStack { Text("Paces on"); Spacer(); Text(p.map { $0.on > 0 ? "\($0.on)" : "—" } ?? "—").monospacedDigit().bold() }
                }
                Stepper(value: Binding(get: { p?.off ?? 0 }, set: { var n = p ?? PinSpot(); n.off = max(0, min(30, $0)); set(h.n, n, wait: true) }), in: 0...30) {
                    HStack { Text(p?.s == "L" ? "From the left" : "From the right"); Spacer(); Text(p.map { $0.off > 0 ? "\($0.off)" : "—" } ?? "—").monospacedDigit().bold() }
                }
                .disabled(p == nil || p?.s == "C")
                Group {
                    if let p { Text("Golfers see: ").foregroundStyle(FC.muted) + Text("⚑ Pin \(p.label.lowercased())").bold() + Text(p.paces.isEmpty ? " and their yards to the pin." : " (\(p.paces)) and their yards to the pin.").foregroundStyle(FC.muted) }
                    else { Text("No pin set: golfers see the green without a flag.").foregroundStyle(FC.muted) }
                }
                .font(.caption)
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(FC.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                if p != nil {
                    Button(role: .destructive) { set(h.n, nil) } label: { Label("Take this pin off", systemImage: "xmark.circle") }.buttonStyle(.borderless)
                }
            }
            .padding(14)
            .background(FC.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(FC.line))
        }
    }

    /// Show it at once and send it; paces wait a moment so holding + sends one change, not twenty.
    private func set(_ n: Int, _ p: PinSpot?, wait: Bool = false) {
        pending[n] = .some(p)
        saving?.cancel()
        saving = Task {
            if wait { try? await Task.sleep(for: .milliseconds(600)); if Task.isCancelled { return } }
            let body: [String: Any] = ["hole": n, "pin": p.map { $0.json } ?? NSNull()]
            if await doc.day("pinsheet", body) == nil { pending[n] = nil }   // it didn't save: show what the server has
        }
    }
    private func clearAll() async {
        for h in holes { pending[h.n] = .some(nil) }
        if await doc.day("pinsheet", ["all": [String: Any]()], done: "Pins cleared") == nil { pending = [:] }
    }
}

/// The drawn green (public/golf/gps.js GREEN_PATH, a 150 × 140 box, back at the top), with the pin: a dot on the
/// small ones, a flag on the big one.
struct PinGreen: View {
    var pin: PinSpot?
    var big: Bool
    var body: some View {
        GeometryReader { g in
            let sx = g.size.width / 150, sy = g.size.height / 140
            ZStack(alignment: .topLeading) {
                PinGreenShape().stroke(Color(hex: 0x2a6e3e), style: StrokeStyle(lineWidth: (big ? 10 : 8) * sx, lineJoin: .round))
                PinGreenShape().fill(Color(hex: 0x4fae6e))
                if big {
                    Path { p in
                        for y in [49.0, 88.0] { p.move(to: CGPoint(x: 6 * sx, y: y * sy)); p.addLine(to: CGPoint(x: 146 * sx, y: y * sy)) }
                        for x in [62.0, 98.0] { p.move(to: CGPoint(x: x * sx, y: 4 * sy)); p.addLine(to: CGPoint(x: x * sx, y: 136 * sy)) }
                    }
                    .stroke(.white.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                if let pin {
                    let x = pin.spot.x * sx, y = pin.spot.y * sy
                    if big {
                        Ellipse().fill(Color(hex: 0x0d2a18)).frame(width: 10, height: 5).position(x: x, y: y)
                        Rectangle().fill(.white).frame(width: 2.5, height: 34).position(x: x, y: y - 17)
                        Path { p in p.move(to: CGPoint(x: x, y: y - 34)); p.addLine(to: CGPoint(x: x + 18, y: y - 28)); p.addLine(to: CGPoint(x: x, y: y - 22)); p.closeSubpath() }
                            .fill(Color(hex: 0xe0453a))
                    } else {
                        Circle().fill(Color(hex: 0xe0453a)).overlay(Circle().stroke(.white, lineWidth: 2)).frame(width: 11, height: 11).position(x: x, y: y)
                    }
                }
            }
        }
        .accessibilityHidden(!big)
    }
}

struct PinGreenShape: Shape {
    func path(in r: CGRect) -> Path {
        let sx = r.width / 150, sy = r.height / 140
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + x * sx, y: r.minY + y * sy) }
        var path = Path()
        path.move(to: p(40, 20))
        path.addCurve(to: p(114, 14), control1: p(58, 6), control2: p(92, 4))
        path.addCurve(to: p(140, 70), control1: p(136, 24), control2: p(146, 46))
        path.addCurve(to: p(104, 104), control1: p(134, 92), control2: p(118, 100))
        path.addCurve(to: p(74, 128), control1: p(92, 108), control2: p(86, 118))
        path.addCurve(to: p(18, 118), control1: p(58, 140), control2: p(30, 136))
        path.addCurve(to: p(20, 70), control1: p(6, 100), control2: p(10, 82))
        path.addCurve(to: p(40, 20), control1: p(28, 60), control2: p(24, 40))
        path.closeSubpath()
        return path
    }
}

/// The Mac's Pin sheet page: the course photo, the title, and the board (pins save on their own, no Save button).
struct PinsView: View {
    let doc: DeskDoc
    var body: some View {
        DeskPage(doc: doc, section: .pins, save: false) {
            EmptyView()
        } title: {
            HeroTitle(title: "Pin sheet", size: 52, sub: "Where the pin is on each green today. Golfers see it as soon as you set it.", subBeside: false)
        } content: {
            ScrollView {
                PinBoard(doc: doc, columns: 6)
                    .padding(18)
                    .background(FC.paper, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(color: FC.scrim.opacity(0.18), radius: 15, y: 8)
                    .padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
    }
}
