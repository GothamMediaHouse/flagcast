import SwiftUI
import UIKit

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
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

extension View {
    /// Headings: heavy, condensed, upper case, like the website's Barlow Condensed.
    func fcHeading(_ style: Font.TextStyle = .title2) -> some View {
        font(.system(style, weight: .heavy)).fontWidth(.condensed).textCase(.uppercase)
    }
    /// Small upper-case labels in monospace, like the website's .label.
    func fcLabel() -> some View {
        font(.caption2.monospaced().weight(.medium)).tracking(1.2).textCase(.uppercase).foregroundStyle(Color.fcMuted)
    }
    func fcCard(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(Color.fcCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.fcLine, lineWidth: 1))
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
        case .primary: (.fcFlag, .fcOnFlag, .fcFlag)
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

/// The green bar at the top of a page, with the logo.
struct GreenHeader<Trailing: View>: View {
    var title: String
    var subtitle: String = ""
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Image("Logo").resizable().scaledToFit().frame(height: 22).accessibilityLabel("Flagcast")
                Text(title).fcHeading(.title2).foregroundStyle(Color.fcOnGreen).lineLimit(2)
                if !subtitle.isEmpty { Text(subtitle).fcLabel().foregroundStyle(Color.fcOnGreenMuted) }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fcGreen)
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
