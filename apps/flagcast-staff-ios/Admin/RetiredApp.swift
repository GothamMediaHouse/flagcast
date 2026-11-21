import SwiftUI

/// Flagcast Admin's last version on iPhone and iPad: Admin is now part of Flagcast Manager (sign in there with a
/// Flagcast admin email, or the admin passcode). This app only says so and opens the Manager.
@main
struct RetiredAdminApp: App {
    var body: some Scene { WindowGroup { RetiredView() } }
}

struct RetiredView: View {
    @Environment(\.openURL) private var openURL
    private let green = Color(red: 0x12 / 255, green: 0x36 / 255, blue: 0x28 / 255)
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "building.columns.fill").font(.system(size: 54)).foregroundStyle(Color(red: 0xe8 / 255, green: 0xc5 / 255, blue: 0x47 / 255))
            Text("Admin is now in Flagcast Manager").font(.title.bold()).multilineTextAlignment(.center)
            Text("Open Flagcast Manager and sign in with your Flagcast email, or use the admin passcode in its Settings. The Admin tab appears at the bottom. You can delete this app.")
                .multilineTextAlignment(.center).opacity(0.85)
            Button { openURL(URL(string: "https://testflight.apple.com")!) } label: { Text("Get Flagcast Manager in TestFlight").frame(maxWidth: .infinity, minHeight: 50) }
                .background(.white, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(green).font(.headline)
            Spacer()
        }
        .padding(28).foregroundStyle(.white).frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(green.ignoresSafeArea())
    }
}
