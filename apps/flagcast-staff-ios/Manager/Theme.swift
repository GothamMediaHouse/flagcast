import SwiftUI
import CoreText

// The Flagcast look on iPhone and iPad (apps/flagcast-mac/design/README.md): deep green, paper and solid white cards,
// Barlow Condensed for titles and numbers, a course photo across the top with the title in white at its bottom.

enum FC {
    static let green = Color(hex: 0x123628), green2 = Color(hex: 0x1c4a37)
    static let onGreen = Color(hex: 0xeef3ec), onGreenMuted = Color(hex: 0xa9bdb0)
    static let flag = Color(hex: 0xe8c547), onFlag = Color(hex: 0x1a1a10)
    static let red = Color(hex: 0xc8312b), blue = Color(hex: 0x1f5aa6), ok = Color(hex: 0x2f8a57)
    static let scrim = Color(red: 8 / 255, green: 24 / 255, blue: 17 / 255)
    static let primary = Color(light: 0x123628, dark: 0x2f8a57)
    static let link = Color(light: 0x1c4a37, dark: 0x7be0a4)
    static let paper = Color(light: 0xf2f4ef, dark: 0x0f1713), paper2 = Color(light: 0xe6eae1, dark: 0x16211b)
    static let card = Color(light: 0xffffff, dark: 0x1b2620), ink = Color(light: 0x14201a, dark: 0xe7ece5)
    static let muted = Color(light: 0x56625a, dark: 0x9aa89f), line = Color(light: 0xd3dacf, dark: 0x2a3830)
    static let hairline = Color(light: 0xeef1ea, dark: 0x22302a)

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
        self.init(uiColor: UIColor { t in
            let h = t.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((h >> 16) & 0xff) / 255, green: CGFloat((h >> 8) & 0xff) / 255, blue: CGFloat(h & 0xff) / 255, alpha: 1)
        })
    }
}

// MARK: - buttons

struct GreenButton: ButtonStyle {
    var full = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 16).frame(minHeight: 44).frame(maxWidth: full ? .infinity : nil)
            .background(FC.primary.opacity(enabled ? (c.isPressed ? 0.8 : 1) : 0.45), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
    }
}
struct PlainCardButton: ButtonStyle {
    var full = false
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: 15, weight: .semibold)).foregroundStyle(FC.ink)
            .padding(.horizontal, 14).frame(minHeight: 44).frame(maxWidth: full ? .infinity : nil)
            .background(FC.card.opacity(c.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(FC.line))
            .contentShape(Rectangle())
    }
}
/// Over a photo: solid white, green text.
struct WhiteButton: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: 14, weight: .semibold)).foregroundStyle(FC.green)
            .padding(.horizontal, 14).frame(minHeight: 36)
            .background(Color.white.opacity(c.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 9))
    }
}

/// Over a photo, the Mac's glass toolbar button: white at 16% with a blur and a 35% white border.
struct GlassButton: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 12).frame(minHeight: 36)
            .background(.ultraThinMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
            .background(Color.white.opacity(c.isPressed ? 0.28 : 0.16), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.35)))
            .environment(\.colorScheme, .dark)
    }
}

/// The Mac's frosted strip of numbers on the photo's bottom edge (Overview): label, big number, a line under it.
struct StatCell: Identifiable {
    var label: String, value: String, sub: String, color: Color = FC.ink
    var id: String { label }
}
struct StatsStrip: View {
    let cells: [StatCell]
    var columns = 2
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: columns), spacing: 1) {
            ForEach(cells) { c in
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.label).font(.system(size: 12, weight: .semibold)).foregroundStyle(FC.muted)
                    Text(c.value).font(FC.display(30)).foregroundStyle(c.color).lineLimit(1).minimumScaleFactor(0.6)
                    Text(c.sub).font(.system(size: 11)).foregroundStyle(FC.muted).lineLimit(1)
                }
                .padding(.horizontal, 14).padding(.vertical, 11).frame(maxWidth: .infinity, alignment: .leading)
                .background(FC.card.opacity(0.94))
            }
        }
        .background(FC.line)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: FC.scrim.opacity(0.18), radius: 15, y: 8)
    }
}

/// The tab bar in the Mac sidebar's green, the open tab in cream (design/Sidebar.dc.html).
enum GreenBars {
    static let cream = UIColor(red: 0xf4 / 255, green: 0xec / 255, blue: 0xd0 / 255, alpha: 1)
    static func apply() {
        let a = UITabBarAppearance()
        a.configureWithOpaqueBackground()
        a.backgroundColor = UIColor(red: 0x12 / 255, green: 0x36 / 255, blue: 0x28 / 255, alpha: 1)
        a.shadowColor = .clear
        for l in [a.stackedLayoutAppearance, a.inlineLayoutAppearance, a.compactInlineLayoutAppearance] {
            l.normal.iconColor = UIColor.white.withAlphaComponent(0.7)
            l.normal.titleTextAttributes = [.foregroundColor: UIColor.white.withAlphaComponent(0.7)]
            l.selected.iconColor = cream
            l.selected.titleTextAttributes = [.foregroundColor: cream]
        }
        UITabBar.appearance().standardAppearance = a
        UITabBar.appearance().scrollEdgeAppearance = a
    }
}

// MARK: - cards and labels

extension View {
    /// A solid white card (radius 14, soft shadow).
    func card(padding: CGFloat = 16) -> some View {
        self.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(FC.card, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: FC.scrim.opacity(0.10), radius: 10, y: 4)
    }
}

struct LiveChip: View {
    var text = "LIVE"
    var body: some View {
        Text(text).font(.system(size: 11, weight: .bold)).tracking(0.8).foregroundStyle(FC.onFlag)
            .padding(.horizontal, 7).padding(.vertical, 3).background(FC.flag, in: RoundedRectangle(cornerRadius: 4))
    }
}
struct CardTitle: View {
    var text: String
    init(_ t: String) { text = t }
    var body: some View { Text(text.uppercased()).font(.system(size: 12, weight: .bold)).tracking(1).foregroundStyle(FC.muted) }
}
struct Help: View {
    var text: String
    init(_ t: String) { text = t }
    var body: some View { Text(text).font(.footnote).foregroundStyle(FC.muted).fixedSize(horizontal: false, vertical: true) }
}

/// A course photo, or the green while it loads (or when there's no course yet).
struct CourseHeroImage: View {
    var image: UIImage?
    var body: some View {
        LinearGradient(colors: [FC.green2, FC.green], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay { if let image { Image(uiImage: image).resizable().aspectRatio(contentMode: .fill).transition(.opacity) } }
            .clipped()
            .animation(.easeOut(duration: 0.4), value: image != nil)
    }
}

/// The page header: the course photo full width under a clear nav bar, dark at the bottom, with a small line
/// (date, LIVE) and the big white title at its bottom.
struct PhotoHeader<Accessory: View>: View {
    var image: UIImage?
    var kicker: String? = nil
    var live = false
    var title: String
    var sub: String? = nil
    var height: CGFloat = 230
    @ViewBuilder var accessory: Accessory

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CourseHeroImage(image: image)
            LinearGradient(stops: [.init(color: FC.scrim.opacity(0.55), location: 0), .init(color: FC.scrim.opacity(0.05), location: 0.35),
                                   .init(color: FC.scrim.opacity(0.85), location: 1)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                if live || kicker != nil {
                    HStack(spacing: 8) {
                        if live { LiveChip() }
                        if let kicker { Text(kicker.uppercased()).font(.system(size: 12, weight: .bold)).tracking(1.2).foregroundStyle(live ? .white : FC.flag) }
                    }
                }
                Text(title).font(FC.display(44)).lineLimit(2).minimumScaleFactor(0.5)
                if let sub { Text(sub).font(.system(size: 14)).opacity(0.9).lineLimit(2) }
                accessory.padding(.top, 6)
            }
            .foregroundStyle(.white).shadow(color: .black.opacity(0.35), radius: 8, y: 1)
            .padding(.horizontal, 20).padding(.bottom, 18)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}
extension PhotoHeader where Accessory == EmptyView {
    init(image: UIImage?, kicker: String? = nil, live: Bool = false, title: String, sub: String? = nil, height: CGFloat = 230) {
        self.init(image: image, kicker: kicker, live: live, title: title, sub: sub, height: height) { EmptyView() }
    }
}

/// A scrolling page under a photo header: the photo runs under the (clear) navigation bar.
struct PhotoPage<Accessory: View, Content: View>: View {
    var image: UIImage?
    var kicker: String? = nil
    var live = false
    var title: String
    var sub: String? = nil
    var height: CGFloat = 250
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PhotoHeader(image: image, kicker: kicker, live: live, title: title, sub: sub, height: height) { accessory }
                VStack(alignment: .leading, spacing: 14) { content }
                    .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 100)
                    .frame(maxWidth: 820).frame(maxWidth: .infinity)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(FC.paper)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

struct FlagcastMark: View {
    var size: CGFloat = 34
    var body: some View { Image("Mark").resizable().frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.24)) }
}

/// "SAT NOV 21" for a yyyy-mm-dd date.
func dayLine(_ s: String) -> String? {
    guard let d = ISO8601DateFormatter.day.date(from: s) else { return nil }
    return d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased()
}

/// A short message at the bottom (saved, sent, errors).
struct NoticeBar: View {
    var text: String?
    var body: some View {
        if let text {
            Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(FC.onGreen).multilineTextAlignment(.center)
                .padding(.horizontal, 16).padding(.vertical, 10).background(FC.green, in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3).padding(.horizontal, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - card pages (More, Settings, Admin lists): the same look as the tournament tabs

/// A page with the photo (or green) header, its title at the bottom, and solid cards below.
struct CardPage<Content: View>: View {
    var image: UIImage? = nil
    var kicker: String? = nil
    var title: String
    var sub: String? = nil
    var height: CGFloat = 190
    @ViewBuilder var content: Content
    var body: some View {
        PhotoPage(image: image, kicker: kicker, title: title, sub: sub, height: height) { EmptyView() } content: { content }
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
    }
}

/// A titled white card holding rows.
struct CardBox<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { CardTitle(title).padding(.leading, 4) }
            VStack(alignment: .leading, spacing: 0) { content }
                .background(FC.card, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: FC.scrim.opacity(0.10), radius: 10, y: 4)
            if let footer { Help(footer).padding(.horizontal, 4) }
        }
    }
}

/// One row in a card: icon, title and a line under it, something on the right, a hairline under it.
struct ListRow<Trailing: View>: View {
    var icon: String? = nil
    var iconColor: Color = FC.primary
    /// a club's logo (or initials) in place of the icon: Admin's tournament rows
    var club: (logo: URL?, name: String)? = nil
    var title: String
    var sub: String? = nil
    var last = false
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 12) {
            if let club { ClubLogoTile(url: club.logo, name: club.name, size: 32) }
            else if let icon {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 32, height: 32).background(iconColor, in: RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(FC.ink)
                if let sub, !sub.isEmpty { Text(sub).font(.footnote).foregroundStyle(FC.muted).lineLimit(2) }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14).frame(minHeight: 58)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(FC.hairline).frame(height: 1).padding(.leading, icon == nil ? 14 : 58) } }
    }
}
extension ListRow where Trailing == EmptyView {
    init(icon: String? = nil, iconColor: Color = FC.primary, title: String, sub: String? = nil, last: Bool = false) {
        self.init(icon: icon, iconColor: iconColor, title: title, sub: sub, last: last) { EmptyView() }
    }
}
/// The chevron for rows that open a page.
struct Chevron: View { var body: some View { Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(FC.muted) } }

/// A text box on a card: paper background, rounded.
struct BoxField: View {
    var placeholder: String
    @Binding var text: String
    var secure = false
    var body: some View {
        Group {
            if secure { SecureField(placeholder, text: $text) } else { TextField(placeholder, text: $text) }
        }
        .padding(12).background(FC.paper2, in: RoundedRectangle(cornerRadius: 10))
    }
}
