import SwiftUI

#if os(macOS)
func copy(_ s: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string) }
#else
func copy(_ s: String) { UIPasteboard.general.string = s }
#endif

extension ISO8601DateFormatter {
    static let day: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; return f }()
}
