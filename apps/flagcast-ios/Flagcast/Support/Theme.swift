import SwiftUI
import UIKit
import CoreText
import MapKit

/// Flagcast's colours (the same tokens as public/golf/golf.css), with the dark-mode values the website uses.
extension Color {
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
    static let fcGreen = dyn(0x123628, 0x0b2219)
    static let fcGreen2 = dyn(0x1c4a37, 0x143829)
    static let fcFlag = dyn(0xe8c547, 0xf0cf55)
    static let fcOnFlag = Color(UIColor(hex: 0x1a1a10))
    static let fcRed = dyn(0xc8312b, 0xf06a5e)
    static let fcPaper = dyn(0xf2f4ef, 0x0f1713)
    static let fcPaper2 = dyn(0xe6eae1, 0x16211b)
    static let fcCard = dyn(0xffffff, 0x17231d)
    static let fcInk = dyn(0x14201a, 0xe7ece5)
    static let fcMuted = dyn(0x56625a, 0x9aa89f)
    static let fcLine = dyn(0xd3dacf, 0x2a3830)
    static let fcOnGreen = Color(UIColor(hex: 0xeef3ec))
    static let fcOnGreenMuted = dyn(0xa9bdb0, 0xa3b8aa)
    static let fcOK = dyn(0x2f8a57, 0x5cc48a)
    static let fcWarn = dyn(0xb7791f, 0xe0a64a)
    /// main buttons: the flag green (a lighter green in dark mode), as in Flagcast Manager
    static let fcPrimary = dyn(0x123628, 0x2f8a57)
    static let fcScrim = Color(UIColor(hex: 0x081811))
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

/// Barlow Condensed (bundled, OFL): the Flagcast titles and big numbers, as in Flagcast Manager.
enum FCType {
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .custom(weight == .bold ? "BarlowCondensed-Bold" : "BarlowCondensed-SemiBold", size: size)
    }
    static func registerFonts() {
        for name in ["BarlowCondensed-Bold", "BarlowCondensed-SemiBold"] {
            if let u = Bundle.main.url(forResource: name, withExtension: "ttf") { CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil) }
        }
    }
    static func size(_ s: Font.TextStyle) -> CGFloat {
        switch s { case .largeTitle: 44; case .title: 36; case .title2: 30; case .title3: 26; case .headline: 22; case .subheadline: 19; default: 22 }
    }
}

extension View {
    /// Headings: Barlow Condensed, upper case (the Manager and website look).
    func fcHeading(_ style: Font.TextStyle = .title2) -> some View {
        font(FCType.display(FCType.size(style))).textCase(.uppercase)
    }
    /// Small upper-case labels in monospace, like the website's .label.
    func fcLabel() -> some View {
        font(.caption2.monospaced().weight(.medium)).tracking(1.2).textCase(.uppercase).foregroundStyle(Color.fcMuted)
    }
    /// A solid white card with a soft shadow (no see-through panels).
    func fcCard(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(Color.fcCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color(UIColor(hex: 0x081811)).opacity(0.10), radius: 10, y: 4)
    }
}

/// Big buttons for use in a cart, in sunlight: flag yellow, dark green, or plain.
struct FCButton: ButtonStyle {
    enum Kind { case primary, dark, plain, danger }
    var kind: Kind = .plain
    var full = true
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let (bg, fg, border): (Color, Color, Color) = switch kind {
        case .primary: (.fcPrimary, .white, .fcPrimary)
        case .dark: (.fcGreen, .fcOnGreen, .fcGreen)
        case .plain: (.fcCard, .fcInk, .fcLine)
        case .danger: (.fcCard, .fcRed, .fcLine)
        }
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: full ? .infinity : nil, minHeight: 50)
            .padding(.horizontal, 16)
            .foregroundStyle(fg)
            .background(bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(border, lineWidth: 1.5))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
extension ButtonStyle where Self == FCButton {
    static var fcPrimary: FCButton { FCButton(kind: .primary) }
    static var fcDark: FCButton { FCButton(kind: .dark) }
    static var fcPlain: FCButton { FCButton(kind: .plain) }
    static var fcDanger: FCButton { FCButton(kind: .danger) }
    static func fc(_ kind: FCButton.Kind, full: Bool) -> FCButton { FCButton(kind: kind, full: full) }
}

/// The LIVE / OFFLINE pill in the green header.
struct LivePill: View {
    var online: Bool
    var offText = "Reconnecting"
    var body: some View {
        Text(online ? "Live" : offText)
            .font(.caption2.monospaced().weight(.semibold)).tracking(1).textCase(.uppercase)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(online ? Color.fcFlag : Color.fcRed, in: RoundedRectangle(cornerRadius: 3))
            .foregroundStyle(online ? Color.fcOnFlag : .white)
            .accessibilityLabel(online ? "Live" : offText)
    }
}

/// The logo golfers see: the club's (from the server, kept in memory once loaded), or the Flagcast logo for demos and
/// clubs that haven't added one. Club logos get a little more height: they're often taller than wide.
struct BrandMark: View {
    var brand: Brand
    var height: CGFloat = 20
    var body: some View {
        if let u = brand.logoURL {
            ClubLogo(url: u).frame(height: height * 1.8, alignment: .leading).frame(maxWidth: 200, alignment: .leading)
                .accessibilityLabel(brand.club.isEmpty ? "Club logo" : brand.club)
        } else {
            Image("Logo").resizable().scaledToFit().frame(height: height).accessibilityLabel("Flagcast")
        }
    }
}
/// a club logo by address (PNG/JPEG/WebP; SVG is drawn by the web pages only, so it shows as text here)
struct ClubLogo: View {
    let url: URL
    @State private var image: UIImage?
    private static var cache: [URL: UIImage] = [:]
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() } else { Color.clear }
        }
        .task(id: url) {
            if let c = Self.cache[url] { image = c; return }
            guard let (d, _) = try? await URLSession.shared.data(from: url), let i = UIImage(data: d) else { return }
            Self.cache[url] = i; image = i
        }
    }
}

/// The top of a page: the course photo (from the tournament's course map) with a dark fade, the logo, and the big
/// white title at its bottom, as in Flagcast Manager. Plain green when the course isn't mapped.
struct GreenHeader<Trailing: View>: View {
    var title: String
    var subtitle: String = ""
    var state: EventState? = nil
    var height: CGFloat = 170
    @ViewBuilder var trailing: Trailing
    @State private var photo: UIImage?
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color.fcGreen2, Color.fcGreen], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay { if let photo { Image(uiImage: photo).resizable().aspectRatio(contentMode: .fill).transition(.opacity) } }
                .clipped()
            LinearGradient(stops: [.init(color: Color.fcScrim.opacity(0.45), location: 0), .init(color: Color.fcScrim.opacity(0.1), location: 0.4),
                                   .init(color: Color.fcScrim.opacity(0.85), location: 1)], startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    BrandMark(brand: state?.brand ?? Brand(), height: 20)
                    if state?.brand.powered == true { Text("POWERED BY FLAGCAST").font(.caption2.monospaced()).tracking(1).foregroundStyle(.white.opacity(0.7)) }
                    Text(title).font(FCType.display(34)).textCase(.uppercase).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.6)
                    if !subtitle.isEmpty { Text(subtitle).font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.85)).lineLimit(2) }
                }
                .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
                Spacer(minLength: 8)
                trailing
            }
            .padding(.horizontal, 16).padding(.bottom, 14)
        }
        .frame(height: photo == nil ? max(110, height - 50) : height)
        .frame(maxWidth: .infinity)
        .clipped()
        .animation(.easeOut(duration: 0.4), value: photo != nil)
        .task(id: state?.id) { if let state { photo = await CoursePhoto.course(state) } }
    }
}

/// Apple Maps satellite pictures of the tournament's own course and holes (no stock photos), made once and kept.
@MainActor
enum CoursePhoto {
    private static var memory: [String: UIImage] = [:]
    static func course(_ s: EventState) async -> UIImage? {
        let pts = s.map.holes.values.flatMap { [$0.tee, $0.m ?? $0.f].compactMap { $0 } }
        guard pts.count >= 2 else { return nil }
        let lats = pts.map(\.lat), lngs = pts.map(\.lng)
        let c = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lngs.min()! + lngs.max()!) / 2)
        let span = max(700, max((lats.max()! - lats.min()!) * 111_000, (lngs.max()! - lngs.min()!) * 111_000 * cos(c.latitude * .pi / 180)) * 1.15)
        return await snap("course-\(s.id)-\(Int(c.latitude * 1e4))-\(Int(c.longitude * 1e4))", MKMapCamera(lookingAtCenter: c, fromDistance: span * 1.25, pitch: 0, heading: 0), CGSize(width: 1200, height: 600))
    }
    /// One hole, tee at the bottom and green at the top.
    static func hole(_ s: EventState, _ n: Int) async -> UIImage? {
        guard let h = s.map.holes[n], let t = h.tee, let g = h.m ?? h.f else { return nil }
        let c = CLLocationCoordinate2D(latitude: (t.lat + g.lat) / 2, longitude: (t.lng + g.lng) / 2)
        let d = CLLocation(latitude: t.lat, longitude: t.lng).distance(from: CLLocation(latitude: g.lat, longitude: g.lng))
        let rad = Double.pi / 180, dl = (g.lng - t.lng) * rad
        let brg = atan2(sin(dl) * cos(g.lat * rad), cos(t.lat * rad) * sin(g.lat * rad) - sin(t.lat * rad) * cos(g.lat * rad) * cos(dl)) / rad
        return await snap("hole-\(s.id)-\(n)-\(Int(t.lat * 1e5))-\(Int(g.lat * 1e5))", MKMapCamera(lookingAtCenter: c, fromDistance: max(260, d * 1.7), pitch: 0, heading: (brg + 360).truncatingRemainder(dividingBy: 360)), CGSize(width: 900, height: 500))
    }
    private static func snap(_ key: String, _ cam: MKMapCamera, _ size: CGSize) async -> UIImage? {
        if let m = memory[key] { return m }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("course-photos")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(key + ".jpg")
        if let d = try? Data(contentsOf: file), let i = UIImage(data: d) { memory[key] = i; return i }
        let o = MKMapSnapshotter.Options()
        o.camera = cam; o.size = size
        o.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
        o.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        guard let shot = try? await MKMapSnapshotter(options: o).start() else { return nil }
        memory[key] = shot.image
        if let j = shot.image.jpegData(compressionQuality: 0.8) { try? j.write(to: file, options: .atomic) }
        return shot.image
    }
}

/// Number formatting shared by the pages.
enum Fmt {
    static func money(_ v: Double) -> String {
        let a = abs(v)
        return a == a.rounded() ? "$\(Int(a))" : String(format: "$%.2f", a)
    }
    static func dollars(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return "$" + (f.string(from: NSNumber(value: jsRound(v))) ?? "\(Int(v))")
    }
    static func time(_ ms: Double) -> String {
        Date(timeIntervalSince1970: ms / 1000).formatted(date: .omitted, time: .shortened)
    }
    static func firstName(_ n: String) -> String { n.split(separator: " ").first.map(String.init) ?? n }
}
