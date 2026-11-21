import SwiftUI

#if os(macOS)
func copy(_ s: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string) }
#else
func copy(_ s: String) { UIPasteboard.general.string = s }
#endif

extension ISO8601DateFormatter {
    // a tournament day ("2026-11-21") is a day where the club is, not midnight in London: without the local time zone
    // it read a day early in the Americas, and "today" turned into tomorrow in the evening
    static let day: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; f.timeZone = .current; return f }()
}
