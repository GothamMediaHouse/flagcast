import SwiftUI

func copy(_ s: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string) }

extension ISO8601DateFormatter {
    static let day: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; return f }()
}
extension Color {
    static let fcGreen = Color(red: 0x12 / 255, green: 0x36 / 255, blue: 0x28 / 255)
    static let fcFlag = Color(red: 0xe3 / 255, green: 0xbd / 255, blue: 0x36 / 255)
}
