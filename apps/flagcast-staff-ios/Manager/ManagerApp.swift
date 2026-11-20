import SwiftUI

@main
struct ManagerApp: App {
    var body: some Scene {
        WindowGroup { ShellView(config: AppConfig(name: "Flagcast Manager", startPath: "/golf/", agent: "FlagcastManagerApp-iOS/1.0")) }
    }
}
