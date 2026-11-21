import SwiftUI
import AuthenticationServices

/// The "Sign in with Apple" button (Face ID / Touch ID): hands back Apple's identity token for the server to check
/// (POST /golf/api/club/apple). Shared by the Mac and the iPhone and iPad Manager.
struct AppleSignInButton: View {
    var height: CGFloat = 46
    var token: (String) -> Void
    var failed: (String) -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        SignInWithAppleButton(.signIn) { req in
            req.requestedScopes = [.email]
        } onCompletion: { result in
            switch result {
            case .success(let auth):
                if let c = auth.credential as? ASAuthorizationAppleIDCredential, let d = c.identityToken, let t = String(data: d, encoding: .utf8) { token(t) }
                else { failed("Apple didn’t send a sign-in. Try again.") }
            case .failure(let e):
                if (e as? ASAuthorizationError)?.code == .canceled { return }
                failed(e.localizedDescription)
            }
        }
        .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// "Sign in with Google": the website's Google sign-in in a sign-in sheet (ASWebAuthenticationSession); the server
/// hands the Flagcast session back on flagcastmanager://signin?token=…
struct GoogleSignInButton: View {
    var height: CGFloat = 46
    var token: (String) -> Void
    var failed: (String) -> Void
    @Environment(\.webAuthenticationSession) private var session
    var body: some View {
        Button {
            Task {
                do {
                    let url = URL(string: "\(Server.base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/golf/signin/google/?app=1")!
                    let back = try await session.authenticate(using: url, callbackURLScheme: "flagcastmanager", preferredBrowserSession: .ephemeral)
                    let q = URLComponents(url: back, resolvingAgainstBaseURL: false)?.queryItems ?? []
                    if let t = q.first(where: { $0.name == "token" })?.value, !t.isEmpty { token(t) }
                    else { failed(q.first(where: { $0.name == "error" })?.value ?? "That Google sign-in didn’t work. Try again.") }
                } catch {
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return }
                    failed(error.localizedDescription)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text("G").font(.system(size: 18, weight: .bold)).foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                Text("Sign in with Google").font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.12))
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 0.85, green: 0.85, blue: 0.85)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
