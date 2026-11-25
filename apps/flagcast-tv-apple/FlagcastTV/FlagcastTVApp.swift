import SwiftUI
import UIKit

/// Flagcast TV for Apple TV: the club's leaderboard screen. Native, because tvOS has no web views; it draws the same
/// pages as the web board (public/golf/board/) from the feed flagcast.app builds for TVs (tvfeed.js).
@main
struct FlagcastTVApp: App {
    @State private var store = TVStore()
    var body: some Scene {
        WindowGroup {
            Root(store: store)
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true; store.start() }   // a club screen never sleeps
        }
    }
}

struct Root: View {
    let store: TVStore
    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch store.screen {
            case .starting: ProgressView().tint(Theme.dim)
            case .pairing: PairView(hello: store.hello, problem: store.problem) { store.watchDemo() }
            case .idle: if let n = store.now { IdleView(now: n) }
            case .live: if let n = store.now, let f = n.feed { BoardView(feed: f, eventName: n.event?.name ?? "") }
            }
            if store.offline {
                VStack { Spacer(); HStack { Text("Reconnecting…").font(.system(size: 22, design: .monospaced)).foregroundStyle(Theme.red)
                    .padding(.horizontal, 14).padding(.vertical, 6).background(.black.opacity(0.6), in: .rect(cornerRadius: 8)); Spacer() } }
                    .padding(40)
            }
        }
        .overlay(alignment: .topTrailing) {
            if store.demo && store.screen == .live {
                // focusable, so the remote has something to press and Menu reaches onExitCommand
                Button { store.stopDemo() } label: {
                    Text("DEMO · CONNECT YOUR CLUB").font(Theme.mono(18, .semibold)).tracking(2).foregroundStyle(Color(hex: "1a1a10"))
                        .padding(.horizontal, 14).padding(.vertical, 6).background(Theme.flag, in: .rect(cornerRadius: 8))
                }
                .buttonStyle(.plain).padding(40)
            }
        }
        // Menu on the remote leaves the demo for the code screen (and nothing else: a club screen keeps playing)
        .onExitCommand(perform: store.demo ? { store.stopDemo() } : nil)
        .animation(.easeInOut(duration: 0.5), value: store.screen)
    }
}

enum Theme {
    static let bg = Color(hex: "0a120e"), panel = Color(hex: "0d1a14"), row = Color(hex: "10201a"), rule = Color(hex: "1d3328")
    static let txt = Color(hex: "eef3ec"), dim = Color(hex: "8fa596"), flag = Color(hex: "e8c547"), red = Color(hex: "ff6b5e"), green = Color(hex: "123628")
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy).width(.condensed) }
    static func mono(_ size: CGFloat, _ w: Font.Weight = .medium) -> Font { .system(size: size, weight: w, design: .monospaced) }
}

extension Color {
    init(hex: String) {
        var v: UInt64 = 0; Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
    /// the club's accent, or Flagcast's flag yellow
    static func accent(_ hex: String) -> Color { hex.range(of: "^#?[0-9a-fA-F]{6}$", options: .regularExpression) != nil ? Color(hex: hex) : Theme.flag }
}
