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
