import SwiftUI
import SafariServices
import UIKit

/// A score with its scorecard mark: circle for birdie, double circle for eagle, square for bogey, double square worse.
struct ScoreMark: View {
    var value: Int?
    var par: Int
    var size: CGFloat = 26
    var body: some View {
        let m = Core.mark(value, par)
        let red = m == .birdie || m == .eagle
        Text(value == nil ? "" : value == 0 ? "PU" : "\(value!)")
            .font(.system(size: size * 0.5, weight: .semibold, design: .monospaced))
            .minimumScaleFactor(0.6)
            .foregroundStyle(red ? Color.fcRed : Color.fcInk)
            .frame(width: size, height: size)
            .overlay {
                switch m {
                case .birdie: Circle().stroke(Color.fcRed, lineWidth: 1.5)
                case .eagle: ZStack { Circle().stroke(Color.fcRed, lineWidth: 1.5); Circle().inset(by: 3).stroke(Color.fcRed, lineWidth: 1.2) }
                case .bogey: Rectangle().stroke(Color.fcInk, lineWidth: 1.2)
                case .double: ZStack { Rectangle().stroke(Color.fcInk, lineWidth: 1.2); Rectangle().inset(by: 3).stroke(Color.fcInk, lineWidth: 1) }
                case .none: EmptyView()
                }
            }
            .accessibilityLabel(value == nil ? "No score" : value == 0 ? "Picked up" : "\(value!)\(m == .none ? "" : ", \(m.rawValue)")")
    }
}

/// A team's 18-hole card: hole numbers, pars and each player's scores with marks. Scrolls sideways.
struct CardGrid: View {
    var holes: [Hole]
    var rows: [(name: String, scores: [Int?])]
    var showTotal = false
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .center, horizontalSpacing: 2, verticalSpacing: 4) {
                GridRow {
                    Text("Hole").fcLabel().gridColumnAlignment(.leading)
                    ForEach(holes, id: \.n) { h in Text("\(h.n)").font(.caption.monospaced()).foregroundStyle(Color.fcMuted).frame(width: 26) }
                    if showTotal { Text("Tot").font(.caption.monospaced()).foregroundStyle(Color.fcMuted).frame(width: 34) }
                }
                GridRow {
                    Text("Par").fcLabel()
                    ForEach(holes, id: \.n) { h in Text("\(h.par)").font(.caption.monospaced()).foregroundStyle(Color.fcMuted) }
                    if showTotal { Text("\(holes.reduce(0) { $0 + $1.par })").font(.caption.monospaced()).foregroundStyle(Color.fcMuted) }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    GridRow {
                        Text(r.name).font(.subheadline.weight(.semibold)).lineLimit(1).padding(.trailing, 8)
                        ForEach(holes, id: \.n) { h in ScoreMark(value: h.n - 1 < r.scores.count ? r.scores[h.n - 1] : nil, par: h.par) }
                        if showTotal {
                            let t = holes.reduce(0) { sum, h in sum + (h.n - 1 < r.scores.count ? max(0, r.scores[h.n - 1] ?? 0) : 0) }
                            Text(t > 0 ? "\(t)" : "").font(.footnote.monospaced().weight(.semibold))
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// A sponsor's logo (from the data: URL the desk uploaded) or its name in bold.
struct SponsorBadge: View {
    var sponsor: Sponsor
    var height: CGFloat = 26
    var body: some View {
        if let img = Self.image(sponsor.logo) {
            Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: 150, maxHeight: height).accessibilityLabel(sponsor.name)
        } else {
            Text(sponsor.name).font(.subheadline.weight(.bold)).foregroundStyle(Color.fcInk)
        }
    }
    private static var cache: [String: UIImage] = [:]
    static func image(_ dataURL: String) -> UIImage? {
        guard dataURL.hasPrefix("data:image/"), let comma = dataURL.firstIndex(of: ",") else { return nil }
        if let c = cache[dataURL] { return c }
        guard let d = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...]), options: .ignoreUnknownCharacters),
              let img = UIImage(data: d) else { return nil }
        cache[dataURL] = img
        return img
    }
}

/// "Presented by <logo> · line" with the sponsor's offer link. Taps are counted for the sponsor report.
struct SponsorLine: View {
    var sponsor: Sponsor
    var lead: String = ""
    var onTap: () -> Void = {}
    @Environment(\.openURL) private var openURL
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if !lead.isEmpty { Text(lead).font(.footnote).foregroundStyle(Color.fcMuted) }
                SponsorBadge(sponsor: sponsor)
                if !sponsor.line.isEmpty { Text("· \(sponsor.line)").font(.footnote).foregroundStyle(Color.fcMuted).lineLimit(2) }
            }
            let label = sponsor.offer.isEmpty ? (sponsor.url.isEmpty ? "" : "Visit \(sponsor.name)") : sponsor.offer
            if !label.isEmpty {
                if let u = URL(string: sponsor.url), !sponsor.url.isEmpty {
                    Button { onTap(); openURL(u) } label: {
                        Label(label, systemImage: "arrow.up.right.square").font(.footnote.weight(.semibold))
                    }
                    .tint(Color.accentColor)
                } else {
                    Text(label).font(.footnote.weight(.semibold)).foregroundStyle(Color.fcGreen2)
                }
            }
        }
    }
}

/// A short message at the bottom of the screen.
struct Toast: ViewModifier {
    @Binding var text: String?
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let t = text {
                Text(t)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Color.fcInk, in: Capsule())
                    .foregroundStyle(Color.fcPaper)
                    .padding(.bottom, 96).padding(.horizontal, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: t) {
                        try? await Task.sleep(for: .seconds(3.2))
                        withAnimation { text = nil }
                    }
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.spring(duration: 0.3), value: text)
    }
}
extension View { func toast(_ text: Binding<String?>) -> some View { modifier(Toast(text: text)) } }

/// Chips that wrap onto more lines (flight filters, screen pages).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > 0 && x + z.width > w { x = 0; y += line + spacing; line = 0 }
            x += z.width + spacing; line = max(line, z.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: min(w, widest), height: y + line)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, line: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > b.minX && x + z.width > b.maxX { x = b.minX; y += line + spacing; line = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(z))
            x += z.width + spacing; line = max(line, z.height)
        }
    }
}

struct Chip: View {
    var title: String
    var on: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).frame(minHeight: 36)
                .background(on ? Color.fcGreen : Color.fcCard, in: Capsule())
                .overlay(Capsule().stroke(on ? Color.fcGreen : Color.fcLine, lineWidth: 1.5))
                .foregroundStyle(on ? Color.fcOnGreen : Color.fcInk)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A web page inside the app (cameras that aren't HLS, sponsor sites).
struct SafariView: UIViewControllerRepresentable {
    var url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let c = SFSafariViewController(url: url)
        c.preferredControlTintColor = UIColor(hex: 0x123628)
        return c
    }
    func updateUIViewController(_ c: SFSafariViewController, context: Context) {}
}
extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

/// Confetti for a hole in one.
struct Confetti: View {
    @State private var start = Date()
    private let pieces: [(x: Double, speed: Double, spin: Double, size: Double, color: Color, delay: Double)] = (0..<90).map { _ in
        (Double.random(in: 0...1), Double.random(in: 0.25...0.6), Double.random(in: -6...6), Double.random(in: 6...12),
         [Color.fcFlag, .fcRed, .white, .fcOK, Color(UIColor(hex: 0x1c4a37))].randomElement()!, Double.random(in: 0...0.8))
    }
    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSince(start)
                for p in pieces {
                    let tt = t - p.delay
                    guard tt > 0 else { continue }
                    let y = -20 + tt * p.speed * size.height
                    guard y < size.height + 20 else { continue }
                    let x = p.x * size.width + sin(tt * 3 + p.spin) * 24
                    var c = ctx
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(tt * p.spin))
                    c.fill(Path(CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2)), with: .color(p.color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Sponsor views and taps, sent in batches for the sponsor report (POST …/hit).
@MainActor
final class SponsorHits {
    let id: String
    private var seen = Set<String>()
    private var queue: [[String: Any]] = []
    private var flush: Task<Void, Never>?
    init(id: String) { self.id = id }
    func view(_ s: String, once: String) { guard !seen.contains(once) else { return }; seen.insert(once); add(s, "view") }
    func tap(_ s: String) { add(s, "tap") }
    private func add(_ s: String, _ k: String) {
        queue.append(["s": s, "k": k, "n": 1])
        flush?.cancel()
        flush = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, !Task.isCancelled else { return }
            let list = Array(self.queue.prefix(50)); self.queue.removeFirst(list.count)
            if !list.isEmpty { _ = try? await API.post(self.id, "hit", ["list": list]) }
        }
    }
}
