import SwiftUI
#if os(macOS)
import WebKit
#else
import SafariServices
#endif

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

// MARK: - Help: a small ? that opens the matching topic of flagcast.app/help inside the app

enum HelpTopic {
    /// "teams" → https://flagcast.app/help/#teams (topics are the ids on the website's Help page)
    static func url(_ topic: String) -> URL { URL(string: "https://flagcast.app/help/#\(topic)")! }
}

struct HelpButton: View {
    var topic: String
    var size: CGFloat = 18
    @State private var open = false
    var body: some View {
        Button { open = true } label: {
            Image(systemName: "questionmark.circle").font(.system(size: size, weight: .regular)).foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Help")
        .accessibilityLabel("Help")
        .sheet(isPresented: $open) { HelpSheet(url: HelpTopic.url(topic)) }
    }
}

#if os(macOS)
struct HelpSheet: View {
    var url: URL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Flagcast Help").font(.headline)
                Spacer()
                Button("Open in Browser") { NSWorkspace.shared.open(url) }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()
            HelpWeb(url: url)
        }
        .frame(minWidth: 920, idealWidth: 1040, minHeight: 640, idealHeight: 760)
    }
}

struct HelpWeb: NSViewRepresentable {
    var url: URL
    func makeNSView(context: Context) -> WKWebView { let w = WKWebView(); w.load(URLRequest(url: url)); return w }
    func updateNSView(_ w: WKWebView, context: Context) {}
}
#else
struct HelpSheet: View {
    var url: URL
    var body: some View { HelpSafari(url: url).ignoresSafeArea() }
}

struct HelpSafari: UIViewControllerRepresentable {
    var url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let c = SFSafariViewController(url: url)
        c.preferredControlTintColor = UIColor(red: 0x12 / 255, green: 0x36 / 255, blue: 0x28 / 255, alpha: 1)
        return c
    }
    func updateUIViewController(_ c: SFSafariViewController, context: Context) {}
}
#endif
