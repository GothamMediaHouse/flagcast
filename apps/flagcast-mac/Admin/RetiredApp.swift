import SwiftUI
import AppKit

/// Flagcast Admin's last version: Admin is now part of Flagcast Manager (sign in there with a Flagcast staff email).
/// This app only says so, opens the Manager, and offers to move itself to the Trash.
@main
struct RetiredAdminApp: App {
    var body: some Scene {
        WindowGroup("Flagcast Admin") { RetiredView().frame(width: 520, height: 360) }
            .windowResizability(.contentSize)
    }
}

struct RetiredView: View {
    private let green = Color(red: 0x12 / 255, green: 0x36 / 255, blue: 0x28 / 255)
    private var manager: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "app.flagcast.manager") }
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 88, height: 88)
            Text("Admin is now in Flagcast Manager").font(.title.bold())
            Text("Open Flagcast Manager and sign in with your Flagcast email. Clubs, Tournaments, Screens & phones and Activity are in its sidebar, under Admin. You can delete this app.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 420)
            HStack(spacing: 10) {
                if let m = manager {
                    Button("Open Flagcast Manager") { NSWorkspace.shared.openApplication(at: m, configuration: .init()); NSApp.terminate(nil) }
                        .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(green)
                } else {
                    Button("Download Flagcast Manager") { NSWorkspace.shared.open(URL(string: "https://flagcast.app/download/manager")!) }
                        .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(green)
                }
                Button("Move This App to the Trash") {
                    NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in DispatchQueue.main.async { NSApp.terminate(nil) } }
                }
            }
        }
        .padding(30)
    }
}
