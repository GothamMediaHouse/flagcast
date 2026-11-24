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
        CardPage(kicker: "Flagcast staff", title: "Admin passcode") {
            VStack(alignment: .leading, spacing: 12) {
                if !(model.admin.pass ?? "").isEmpty {
                    Label("Admin is unlocked on this device", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(FC.ok)
                    Button("Forget the Passcode", role: .destructive) { model.admin.forget() }.buttonStyle(PlainCardButton(full: true))
                } else {
                    BoxField(placeholder: "Admin passcode", text: $text, secure: true).onSubmit(unlock)
                    Button { unlock() } label: { if busy { ProgressView().tint(.white) } else { Text("Unlock Admin") } }.buttonStyle(GreenButton(full: true)).disabled(text.isEmpty || busy)
                    Text(message ?? "Kept in this device’s Keychain. The Admin tab appears at the bottom. Signing in with your Flagcast admin email does the same.")
                        .font(.footnote).foregroundStyle(message == nil ? FC.muted : FC.red)
                }
            }
            .card()
        }
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
    @State private var deleting: EventRef?
    private static var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }

    var body: some View {
        CardPage(kicker: model.me?.club?.stateLine ?? (model.signedIn ? nil : "Not signed in"), title: "Tournaments", sub: model.me?.club?.name) {
            CardBox {
                if model.shownEvents.isEmpty {
                    Text(model.signedIn ? "No tournaments yet. Make one below." : "Sign in to see your club’s tournaments.").foregroundStyle(FC.muted).padding(14)
                }
                ForEach(Array(model.shownEvents.enumerated()), id: \.element.id) { i, e in
                    Button { model.selection = e.id; if asSheet { dismiss() } } label: {
                        ListRow(icon: model.selection == e.id ? "flag.fill" : "flag", iconColor: model.selection == e.id ? FC.primary : FC.muted,
                                title: e.name.isEmpty ? "Tournament" : e.name,
                                sub: [e.date.flatMap(dayLine), e.club].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "), last: i == model.shownEvents.count - 1) {
                            if model.selection == e.id { Image(systemName: "checkmark").font(.headline).foregroundStyle(FC.primary) }
                            Color.clear.frame(width: 34, height: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .trailing) {
                        Menu {
                            Button(role: .destructive) { deleting = e } label: { Label(e.fromClub == true ? "Delete Tournament…" : "Remove from This \(Self.device)…", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(FC.link).frame(width: 44, height: 44).contentShape(Rectangle()) }
                        .accessibilityLabel("More for \(e.name)")
                        .padding(.trailing, 4)
                    }
                    .contextMenu { Button(role: .destructive) { deleting = e } label: { Label(e.fromClub == true ? "Delete Tournament…" : "Remove from This \(Self.device)…", systemImage: "trash") } }
                }
            }
            if model.signedIn {
                CardBox(title: "New tournament") {
                    VStack(alignment: .leading, spacing: 10) {
                        BoxField(placeholder: "Name, e.g. Member-Guest 2027", text: $name)
                        Button { make() } label: { if making { ProgressView().tint(.white) } else { Text("Make a Tournament") } }
                            .buttonStyle(GreenButton(full: true)).disabled(making || !(model.me?.club?.canMake ?? false))
                        if let message { Text(message).font(.footnote).foregroundStyle(FC.red) }
                        else if model.isAdmin && !(model.me?.club?.canMake ?? false) { Text("To make one for a club, go to Admin, open the club, and use New tournament there.").font(.footnote).foregroundStyle(FC.muted) }
                        else if let c = model.me?.club, !c.canMake { Text(c.stateLine).font(.footnote).foregroundStyle(FC.red) }
                        else if model.me?.club == nil { Text("Set up your club first.").font(.footnote).foregroundStyle(FC.red) }
                    }
                    .padding(14)
                }
            }
            CardBox {
                NavigationLink { AddByLinkView() } label: { ListRow(icon: "link.badge.plus", iconColor: FC.ok, title: "Add by desk link", sub: "A tournament someone sent you", last: model.signedIn) { Chevron() } }.buttonStyle(.plain)
                if !model.signedIn {
                    NavigationLink { SignInView() } label: { ListRow(icon: "person.badge.plus", title: "Sign in", sub: "See your club’s tournaments", last: true) { Chevron() } }.buttonStyle(.plain)
                }
            }
            Help("Tap ⋯ beside a tournament to delete it.")
        }
        .toolbar { if asSheet { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } }
        .confirmationDialog(deleting?.fromClub == true ? "Delete \(deleting?.name ?? "this tournament")?" : "Remove \(deleting?.name ?? "this tournament") from this \(Self.device)?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { e in
            Button(e.fromClub == true ? "Delete Tournament" : "Remove", role: .destructive) { Task { await model.remove(e.id) } }
        } message: { e in Text(e.fromClub == true ? "It comes off your club’s list on every phone, iPad and Mac. Its scores and pages stay, so Flagcast can bring it back if you need it." : "You can add it again with its desk link.") }
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
        CardPage(kicker: "Tournaments", title: "Add by desk link") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("https://flagcast.app/g/…/desk#…", text: $link, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(12).background(FC.paper2, in: RoundedRectangle(cornerRadius: 10))
                Button { add() } label: { if busy { ProgressView().tint(.white) } else { Text("Add Tournament") } }.buttonStyle(GreenButton(full: true)).disabled(link.isEmpty || busy)
                Text(message ?? "Paste the desk link the organizer sent you. It looks like …/g/abcd2345/desk#longkey").font(.footnote).foregroundStyle(message == nil ? FC.muted : FC.red)
            }
            .card()
        }
    }
    private func add() {
        busy = true; message = nil
        Task {
            do { try await model.add(link: link.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() } catch { message = error.localizedDescription }
            busy = false
        }
    }
}
