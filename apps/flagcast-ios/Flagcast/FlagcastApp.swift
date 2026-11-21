import SwiftUI

@main
struct FlagcastApp: App {
    @State private var router = Router()
    @Environment(\.scenePhase) private var phase
    @AppStorage("flagcast.textSize") private var textSize = TextSize.standard.rawValue
    init() { FCType.registerFonts() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .modifier(TextSizing(size: TextSize(rawValue: textSize)?.dynamic))
                // cart cards and shared links: flagcast://g/<id>/s/<CODE>, or flagcast.app/g/… handed to the app
                .onOpenURL { router.handle($0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { a in
                    if let u = a.webpageURL { router.handle(u) }
                }
        }
        .onChange(of: phase) { _, p in if p == .active { Feeds.wakeAll() } }
    }
}

enum Route: Hashable {
    case score(id: String, code: String)
    case live(id: String)
    case pro(id: String)
}

@MainActor @Observable
final class Router {
    var path: [Route] = []
    func go(_ r: Route) { path.append(r) }
    /// Open a link from outside the app: it replaces whatever was on screen.
    func handle(_ url: URL) {
        if let r = Codes.route(url.absoluteString) { path = [r] }
    }
}

struct RootView: View {
    @Environment(Router.self) private var router
    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: Route.self) { r in
                    switch r {
                    case let .score(id, code): ScorecardScreen(id: id, code: code)
                    case let .live(id): LeaderboardScreen(id: id)
                    case let .pro(id): ProScreen(id: id)
                    }
                }
        }
        .tint(Color.accentColor)
    }
}

/// Settings → Text size: at least this big (bigger if the iPhone's own setting is bigger)
struct TextSizing: ViewModifier {
    var size: DynamicTypeSize?
    func body(content: Content) -> some View {
        if let size { content.dynamicTypeSize(size...DynamicTypeSize.accessibility3) } else { content }
    }
}
