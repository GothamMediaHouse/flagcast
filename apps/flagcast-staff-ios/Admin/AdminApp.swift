import SwiftUI

@main
struct AdminApp: App {
    var body: some Scene {
        WindowGroup { ShellView(config: AppConfig(name: "Flagcast Admin", startPath: "/golf/admin/", agent: "FlagcastAdminApp-iOS/1.0")) }
    }
}
