import SwiftUI

@main
struct FlagcastApp: App {
    @State private var router = Router()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
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
