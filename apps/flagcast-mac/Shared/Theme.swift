import SwiftUI
import CoreText

// The Flagcast look (design/README.md, approved 2026-11-20): deep green sidebar, full-bleed course photos under a
// clear toolbar, Barlow Condensed for big titles and numbers, white cards raised over the photo's bottom edge.

enum FC {
    static let green = Color(hex: 0x123628), green2 = Color(hex: 0x1c4a37)
    static let onGreen = Color(hex: 0xeef3ec), onGreenMuted = Color(hex: 0xa9bdb0)
    static let flag = Color(hex: 0xe8c547), onFlag = Color(hex: 0x1a1a10)
    static let red = Color(hex: 0xc8312b), blue = Color(hex: 0x1f5aa6), ok = Color(hex: 0x2f8a57)
    static let scrim = Color(red: 8 / 255, green: 24 / 255, blue: 17 / 255)
    /// primary buttons: the flag green in light mode, a lighter green (white text) in dark mode
    static let primary = Color(light: 0x123628, dark: 0x2f8a57)
    /// text links and small text buttons on paper or cards
    static let link = Color(light: 0x1c4a37, dark: 0x7be0a4)
    // content colours, light and dark (golf.css)
    static let paper = Color(light: 0xf2f4ef, dark: 0x0f1713), paper2 = Color(light: 0xe6eae1, dark: 0x16211b)
    static let card = Color(light: 0xffffff, dark: 0x1b2620), ink = Color(light: 0x14201a, dark: 0xe7ece5)
    static let muted = Color(light: 0x56625a, dark: 0x9aa89f), line = Color(light: 0xd3dacf, dark: 0x2a3830)
    static let hairline = Color(light: 0xeef1ea, dark: 0x22302a), head = Color(light: 0xf7f8f4, dark: 0x1b2822)

    /// Barlow Condensed (bundled, OFL) for titles and numbers.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .custom(weight == .bold ? "BarlowCondensed-Bold" : "BarlowCondensed-SemiBold", size: size)
    }
    static func registerFonts() {
        for name in ["BarlowCondensed-Bold", "BarlowCondensed-SemiBold"] {
            if let u = Bundle.main.url(forResource: name, withExtension: "ttf") { CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil) }
        }
    }
}

extension Color {
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255) }
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { a in
            let h = a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(red: CGFloat((h >> 16) & 0xff) / 255, green: CGFloat((h >> 8) & 0xff) / 255, blue: CGFloat(h & 0xff) / 255, alpha: 1)
        })
    }
    static let fcGreen = FC.green
    static let fcFlag = FC.flag
}

// MARK: - buttons

/// Over a photo: white glass (white 16% + blur, 35% white border), white text.
struct GlassButton: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 12).frame(height: 30)
            .background(.ultraThinMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
            .background(Color.white.opacity(c.isPressed ? 0.28 : 0.16), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.35)))
            .environment(\.colorScheme, .dark)
    }
}
/// The main action over a photo: solid white, green text.
struct WhiteButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(FC.green)
            .padding(.horizontal, 14).frame(height: 30)
            .background(Color.white.opacity(enabled ? (c.isPressed ? 0.85 : 1) : 0.55), in: RoundedRectangle(cornerRadius: 7))
    }
}
/// On paper: solid green.
struct GreenButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 14).frame(height: 30)
            .background(FC.primary.opacity(enabled ? (c.isPressed ? 0.8 : 1) : 0.5), in: RoundedRectangle(cornerRadius: 7))
    }
}
/// On paper: white with a line.
struct PlainCardButton: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(FC.ink)
            .padding(.horizontal, 12).frame(height: 30)
            .background(FC.card.opacity(c.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(FC.line))
    }
}

// MARK: - cards, chips

extension View {
    /// A white card raised over the photo: radius 12, shadow 0 8 30 rgba(8,24,17,0.18).
    func raisedCard(padding: CGFloat = 0) -> some View {
        self.padding(padding).background(FC.card, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: FC.scrim.opacity(0.18), radius: 15, y: 8)
    }
    /// A flat card on paper (hairline border).
    func flatCard(padding: CGFloat = 0) -> some View {
        self.padding(padding).background(FC.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(FC.line))
    }
}

struct LiveChip: View {
    var text = "LIVE"
    var body: some View {
        Text(text).font(.system(size: 11, weight: .bold)).tracking(0.8).foregroundStyle(FC.onFlag)
            .padding(.horizontal, 7).padding(.vertical, 3).background(FC.flag, in: RoundedRectangle(cornerRadius: 4))
    }
}
/// A small capital-letters label (TOURNAMENT, TEES, SCORECARD).
struct CardTitle: View {
    var text: String
    init(_ t: String) { text = t }
    var body: some View { Text(text.uppercased()).font(.system(size: 12, weight: .bold)).tracking(1).foregroundStyle(FC.muted) }
}

// MARK: - the photo page

/// Every screen: an edge-to-edge course photo under the header (scrim: dark at the top for the buttons, clear in the
/// middle, dark at the bottom for the title), the header bar with its buttons, the big title, and the content, which
/// starts over the photo's bottom edge.
struct PhotoPage<Actions: View, Title: View, Content: View>: View {
    var image: NSImage?
    var height: CGFloat
    var section: String
    var titleHeight: CGFloat
    @ViewBuilder var actions: Actions
    @ViewBuilder var title: Title
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .top) {
            FC.paper
            CourseHeroImage(image: image).frame(height: height).frame(maxWidth: .infinity).clipped()
                .overlay(LinearGradient(stops: [.init(color: FC.scrim.opacity(0.6), location: 0), .init(color: FC.scrim.opacity(0.1), location: 0.3),
                                                 .init(color: FC.scrim.opacity(0.35), location: 0.6), .init(color: FC.scrim.opacity(0.85), location: 1)],
                                        startPoint: .top, endPoint: .bottom))
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text(section).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    actions
                }
                .padding(.horizontal, 20).frame(height: 52)
                .contentShape(Rectangle()).gesture(WindowDragGesture())
                title.padding(.horizontal, 30).frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: titleHeight, alignment: .bottomLeading).foregroundStyle(.white).clipped()
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea(edges: .top)
    }
}

/// The big Barlow title over a photo, with an optional small line above it and a line beside or below it.
struct HeroTitle: View {
    var kicker: String? = nil
    var kickerColor: Color = FC.flag
    var live = false
    var title: String
    var size: CGFloat = 56
    var sub: String? = nil
    var subBeside = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if live || kicker != nil {
                HStack(spacing: 10) {
                    if live { LiveChip() }
                    if let kicker { Text(kicker.uppercased()).font(.system(size: 12, weight: .bold)).tracking(1.4).foregroundStyle(live ? .white : kickerColor) }
                }
            }
            if subBeside, let sub {
                HStack(alignment: .lastTextBaseline, spacing: 14) {
                    Text(title).font(FC.display(size)).lineLimit(1).minimumScaleFactor(0.6)
                    Text(sub).font(.system(size: 14)).padding(.bottom, 4)
                }
            } else {
                Text(title).font(FC.display(size)).lineLimit(1).minimumScaleFactor(0.5)
                if let sub { Text(sub).font(.system(size: 16)).lineLimit(2) }
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 9, y: 1)
        .padding(.bottom, 18)
    }
}

/// A course photo, or the green with the flag mark while it loads (or when there's no course yet).
struct CourseHeroImage: View {
    var image: NSImage?
    var body: some View {
        // The photo is an overlay, so a wide photo can't make the view wider than the space it's given (it was pushing cards under the sidebar).
        LinearGradient(colors: [FC.green2, FC.green], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay { if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).transition(.opacity) } }
            .clipped()
        .animation(.easeOut(duration: 0.4), value: image != nil)
    }
}

/// The Flagcast mark (cream F on green), drawn from public/golf/brand/mark.svg's colours.
struct FlagcastMark: View {
    var size: CGFloat = 34
    var body: some View {
        Image("Mark").resizable().frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.24))
            .overlay(RoundedRectangle(cornerRadius: size * 0.24).stroke(FC.onGreen.opacity(0.18)))
    }
}
