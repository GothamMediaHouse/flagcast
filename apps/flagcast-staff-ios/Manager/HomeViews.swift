import SwiftUI

/// Sign in: Sign in with Apple (Face ID), email + password, or an emailed code (the first time).
struct SignInView: View {
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var useCode = false
    @State private var sent = false
    @State private var busy = false
    @State private var message: String?
    @State private var passcode = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PhotoHeader(image: nil, kicker: "Flagcast", title: "Run your tournament", sub: "Teams, live scores and the TVs, from your phone.", height: 280)
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        CardTitle("Sign in")
                        AppleSignInButton(height: 50, token: { t in run { try await model.appleSignIn(t) } }, failed: { message = $0 })
                        if model.googleOn { GoogleSignInButton(height: 50, token: { t in run { await model.use(token: t) } }, failed: { message = $0 }) }
                        HStack { Rectangle().fill(FC.line).frame(height: 1); Text("or").font(.caption).foregroundStyle(FC.muted); Rectangle().fill(FC.line).frame(height: 1) }
                        field("Email", $email).textContentType(useCode ? .emailAddress : .username).keyboardType(.emailAddress)
                        if !useCode {
                            SecureField("Password", text: $password).textContentType(.password).padding(12).background(FC.paper2, in: RoundedRectangle(cornerRadius: 10))
                            Button { run { try await model.login(email.trimmingCharacters(in: .whitespaces), password); password = "" } } label: { label("Sign In") }
                                .buttonStyle(GreenButton(full: true)).disabled(!email.contains("@") || password.isEmpty || busy)
                            Button("First time? Email me a code instead") { useCode = true; message = nil }.font(.subheadline).foregroundStyle(FC.link)
                        } else if !sent {
                            Button { start() } label: { label("Email Me a Code") }.buttonStyle(GreenButton(full: true)).disabled(!email.contains("@") || busy)
                            Button("Use a password") { useCode = false; message = nil }.font(.subheadline).foregroundStyle(FC.link)
                        } else {
                            Text("We sent a code to \(email).").font(.subheadline).foregroundStyle(FC.muted)
                            TextField("6-digit code", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode).font(FC.display(30))
                                .padding(12).background(FC.paper2, in: RoundedRectangle(cornerRadius: 10))
                            Button { run { try await model.verify(email.trimmingCharacters(in: .whitespaces), code.trimmingCharacters(in: .whitespaces)) } } label: { label("Sign In") }
                                .buttonStyle(GreenButton(full: true)).disabled(code.count < 4 || busy)
                            Button("Use a different email") { sent = false; code = "" }.font(.subheadline).foregroundStyle(FC.link)
                        }
                        if let message { Text(message).font(.footnote).foregroundStyle(FC.red) }
                    }
                    .card()
                    Help("After your first sign-in with a code, set a password in Settings, or just use Sign in with Apple. Flagcast staff get the Admin tab.")
                    Button("Flagcast admin passcode") { passcode = true }.font(.footnote).foregroundStyle(FC.muted).frame(maxWidth: .infinity)
                    NavigationLink("Have a desk link? Add a tournament without signing in") { AddByLinkView() }
                        .font(.subheadline).foregroundStyle(FC.link).frame(maxWidth: .infinity)
                }
                .padding(16).frame(maxWidth: 520)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(FC.paper)
        .sheet(isPresented: $passcode) { NavigationStack { AdminPasscodeView() } }
        .task { await model.loadConfig() }
    }
    private func field(_ p: String, _ t: Binding<String>) -> some View {
        TextField(p, text: t).textInputAutocapitalization(.never).autocorrectionDisabled().padding(12).background(FC.paper2, in: RoundedRectangle(cornerRadius: 10))
    }
    @ViewBuilder private func label(_ t: String) -> some View { if busy { ProgressView().tint(.white) } else { Text(t) } }
    private func run(_ f: @escaping () async throws -> Void) {
        busy = true; message = nil
        Task { do { try await f() } catch { message = error.localizedDescription }; busy = false }
    }
    private func start() {
        run { let dev = try await model.startSignIn(email.trimmingCharacters(in: .whitespaces)); sent = true; if let dev { code = dev } }
    }
}

/// The Flagcast admin passcode: kept in the Keychain, unlocks the Admin tab without an email sign-in.
struct AdminPasscodeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var busy = false
    @State private var message: String?
    var body: some View {
        Form {
            if !(model.admin.pass ?? "").isEmpty {
                LabeledContent("Flagcast Admin", value: "Unlocked on this device")
                Button("Forget the Passcode", role: .destructive) { model.admin.forget() }
            } else {
                SwiftUI.Section {
                    SecureField("Admin passcode", text: $text).onSubmit(unlock)
                    Button { unlock() } label: { if busy { ProgressView() } else { Text("Unlock Admin") } }.disabled(text.isEmpty || busy)
                } footer: { Text(message ?? "The passcode is kept in this device’s Keychain. The Admin tab appears at the bottom.") }
            }
        }
        .navigationTitle("Admin passcode").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
    private func unlock() {
        busy = true; message = nil
        Task {
            do { try await model.admin.unlock(text); text = ""; dismiss() } catch { message = error.localizedDescription }
            busy = false
        }
    }
}

/// Every tournament this device knows: the club's, ones added by desk link, and ones opened from Admin.
/// Pick one to open it; make a new one; add one by its desk link.
struct TournamentPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var asSheet = false
    @State private var name = ""
    @State private var making = false
    @State private var message: String?

    var body: some View {
        List {
            if let c = model.me?.club {
                SwiftUI.Section { LabeledContent(c.name, value: c.canMake ? (c.credits < 0 ? "Unlimited" : "\(c.credits) left") : "") } footer: { Text(c.stateLine) }
            }
            SwiftUI.Section("Tournaments") {
                if model.shownEvents.isEmpty { Text(model.signedIn ? "No tournaments yet. Make one below." : "Sign in to see your club’s tournaments.").foregroundStyle(FC.muted) }
                ForEach(model.shownEvents) { e in
                    Button { model.selection = e.id; if asSheet { dismiss() } } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.name.isEmpty ? "Tournament" : e.name).font(.headline).foregroundStyle(FC.ink)
                                Text([e.date.flatMap(dayLine), e.club].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(FC.muted)
                            }
                            Spacer()
                            if model.selection == e.id { Image(systemName: "checkmark").foregroundStyle(FC.primary) }
                        }
                    }
                    .swipeActions { Button("Remove", role: .destructive) { Task { await model.remove(e.id) } } }
                }
            }
            if model.signedIn {
                SwiftUI.Section {
                    TextField("New tournament name", text: $name)
                    Button { make() } label: { if making { ProgressView() } else { Text("Make a Tournament") } }
                        .disabled(making || !(model.me?.club?.canMake ?? false))
                } footer: { if let message { Text(message).foregroundStyle(FC.red) } }
            }
            SwiftUI.Section { NavigationLink("Add a tournament by its desk link") { AddByLinkView() } }
            if !model.signedIn {
                SwiftUI.Section { NavigationLink("Sign in with your club email") { SignInView() } }
            }
        }
        .scrollContentBackground(.hidden).background(FC.paper)
        .navigationTitle("Tournaments")
        .toolbar { if asSheet { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } }
        .refreshable { await model.refresh() }
    }
    private func make() {
        making = true; message = nil
        Task {
            do { try await model.create(name); name = ""; if asSheet { dismiss() } } catch { message = error.localizedDescription }
            making = false
        }
    }
}

struct AddByLinkView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var busy = false
    @State private var message: String?
    var body: some View {
        Form {
            SwiftUI.Section {
                TextField("https://flagcast.app/g/…/desk#…", text: $link, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button { add() } label: { if busy { ProgressView() } else { Text("Add Tournament") } }.disabled(link.isEmpty || busy)
            } footer: { Text(message ?? "Paste the desk link the organizer sent you. It looks like …/g/abcd2345/desk#longkey") }
        }
        .navigationTitle("Add by desk link")
    }
    private func add() {
        busy = true; message = nil
        Task {
            do { try await model.add(link: link.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() } catch { message = error.localizedDescription }
            busy = false
        }
    }
}
